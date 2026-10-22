// Purpose: Queries broker-backed status data and presents it through the Tray interface.
#include "TrayBrokerStatus.h"

#include "ClientBrokerStatus.h"

#include <Windows.h>
#include <winsvc.h>
#include <shellapi.h>
#include <sddl.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "BrokerContracts.h"
#include "BrokerPipeClient.h"
#include "BuildVersion.h"
#include "ClientAccountIdentity.h"
#include "ClientLogging.h"
#include "ClientStatusActions.h"
#include "ClientStatusIcon.h"
#include "ClientStatusMenu.h"
#include "ClientUiCommon.h"
#include "ClientWindowsError.h"
#include "TrayLocalization.h"

namespace xucrun::broker_status
{
	using BrokerServiceStatus = status_icon::BrokerServiceStatus;
	using BrokerServiceState = status_icon::BrokerServiceState;

	namespace
	{
		constexpr const wchar_t* BROKER_STATUS_WINDOW_CLASS = L"xucRunBrokerStatusWindow";
		constexpr UINT BROKER_STATUS_CALLBACK = WM_APP + 1;
		constexpr UINT BROKER_SERVICE_STATUS_CHANGED = WM_APP + 2;
		constexpr UINT BROKER_STATUS_SHOW_MENU = WM_APP + 3;
		constexpr UINT BROKER_STATUS_LANGUAGE_CHANGED = WM_APP + 4;
		constexpr UINT_PTR BROKER_STATUS_TIMER = 1;
		constexpr UINT BROKER_STATUS_ACTIVATION_INTERVAL = 250;
		constexpr ULONGLONG BROKER_STATUS_ACTIVATION_TIMEOUT = 15000;
		constexpr UINT BROKER_STATUS_RETRY_INTERVAL = 1000;
		constexpr UINT BROKER_STATUS_ACTIVE_INTERVAL = 2000;
		constexpr UINT BROKER_STATUS_IDLE_INTERVAL = 5000;
		constexpr std::uint32_t BROKER_STATUS_FAILURE_THRESHOLD = 3;

		SC_HANDLE brokerStatusServiceHandle = nullptr;
		SERVICE_NOTIFY_2W brokerServiceNotification = {};
		std::atomic<HWND> brokerServiceNotificationWindow = nullptr;
		std::uint32_t consecutiveBrokerHealthFailures = 0;
		std::uint32_t registeredStatusIconBrokerProcessId = 0;
		bool statusIconRegistryFailureReported = false;
		ULONGLONG brokerActivationRefreshDeadline = 0;
		bool restartStatusIcon = false;

		std::wstring GetStatusIconActivationEventName(std::uint32_t processId)
		{
			return L"Local\\xucRunBrokerStatus.Activate." +
				std::to_wstring(processId);
		}

		void CALLBACK StatusIconActivationSignaled(void* context, BOOLEAN)
		{
			PostMessageW(static_cast<HWND>(context), BROKER_STATUS_SHOW_MENU, 0, 0);
		}

		void CALLBACK StatusIconLanguageChanged(void* context, BOOLEAN)
		{
			PostMessageW(
				static_cast<HWND>(context), BROKER_STATUS_LANGUAGE_CHANGED, 0, 0);
		}

		struct StatusEventRegistration
		{
			HANDLE event = nullptr;
			HANDLE wait = nullptr;
		};

		bool RegisterStatusEvent(const std::wstring& name,
			WAITORTIMERCALLBACK callback, HWND window,
			SECURITY_ATTRIBUTES& security, const wchar_t* purpose,
			StatusEventRegistration& registration)
		{
			registration.event =
				CreateEventW(&security, FALSE, FALSE, name.c_str());
			const DWORD eventError = GetLastError();
			if (!registration.event || eventError == ERROR_ALREADY_EXISTS)
			{
				client_logging::Write(L"Warning",
					L"Creating the status icon " + std::wstring(purpose) +
					L" event failed. Windows error: " +
					std::to_wstring(eventError) + L".");
				if (registration.event)
					CloseHandle(registration.event);
				registration.event = nullptr;
				return false;
			}
			if (RegisterWaitForSingleObject(&registration.wait,
				registration.event, callback, window, INFINITE,
				WT_EXECUTEDEFAULT))
			{
				return true;
			}
			client_logging::Write(L"Warning",
				L"Registering the status icon " + std::wstring(purpose) +
				L" wait failed. Windows error: " +
				std::to_wstring(GetLastError()) + L".");
			CloseHandle(registration.event);
			registration.event = nullptr;
			return false;
		}

		void CloseStatusEvent(StatusEventRegistration& registration)
		{
			if (registration.wait)
				UnregisterWaitEx(registration.wait, INVALID_HANDLE_VALUE);
			if (registration.event)
				CloseHandle(registration.event);
			registration = {};
		}

		bool ActivateStatusIcon(std::uint32_t processId)
		{
			if (processId == 0 || processId == GetCurrentProcessId())
				return false;
			HANDLE event = OpenEventW(EVENT_MODIFY_STATE, FALSE,
				GetStatusIconActivationEventName(processId).c_str());
			if (!event)
			{
				client_logging::Write(L"Warning",
					L"Opening the selected status icon activation event failed. PID: " +
					std::to_wstring(processId) + L"; Windows error: " +
					std::to_wstring(GetLastError()) + L".");
				return false;
			}
			AllowSetForegroundWindow(processId);
			const bool signaled = SetEvent(event) != FALSE;
			const DWORD error = signaled ? NO_ERROR : GetLastError();
			CloseHandle(event);
			if (!signaled)
			{
				client_logging::Write(L"Warning",
					L"Signaling the selected status icon failed. PID: " +
					std::to_wstring(processId) + L"; Windows error: " +
					std::to_wstring(error) + L".");
			}
			return signaled;
		}

		const std::wstring& GetStatusAccount()
		{
			static const std::wstring account = [] {
				std::wstring username;
				std::wstring domain;
				if (!account_identity::GetCurrentUserInfo(username, domain))
					return localization::GetText(
						localization::TextId::StatusAccountUnavailable);
				return domain.empty() ? username : domain + L"\\" + username;
			}();
			return account;
		}

		bool IsStatusProcessElevated()
		{
			static const bool elevated =
				account_identity::IsRunningAsAdministrator();
			return elevated;
		}

		void CALLBACK BrokerServiceStatusChanged(void*)
		{
			const HWND window = brokerServiceNotificationWindow.load();
			if (window)
				PostMessageW(window, BROKER_SERVICE_STATUS_CHANGED, 0, 0);
		}

		bool ArmBrokerServiceStatusNotification(HWND window)
		{
			if (!brokerStatusServiceHandle)
			{
				SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
				if (!manager)
					return false;
				brokerStatusServiceHandle = OpenServiceW(manager,
					broker::BrokerServiceName, SERVICE_QUERY_STATUS);
				CloseServiceHandle(manager);
				if (!brokerStatusServiceHandle)
					return false;
			}

			SERVICE_STATUS_PROCESS status = {};
			DWORD bytesNeeded = 0;
			if (!QueryServiceStatusEx(brokerStatusServiceHandle, SC_STATUS_PROCESS_INFO,
				reinterpret_cast<LPBYTE>(&status), sizeof(status), &bytesNeeded))
			{
				CloseServiceHandle(brokerStatusServiceHandle);
				brokerStatusServiceHandle = nullptr;
				return false;
			}

			DWORD notifyMask = SERVICE_NOTIFY_STOPPED | SERVICE_NOTIFY_START_PENDING |
				SERVICE_NOTIFY_STOP_PENDING | SERVICE_NOTIFY_RUNNING |
				SERVICE_NOTIFY_CONTINUE_PENDING | SERVICE_NOTIFY_PAUSE_PENDING |
				SERVICE_NOTIFY_PAUSED | SERVICE_NOTIFY_DELETE_PENDING;
			switch (status.dwCurrentState)
			{
			case SERVICE_STOPPED: notifyMask &= ~SERVICE_NOTIFY_STOPPED; break;
			case SERVICE_START_PENDING: notifyMask &= ~SERVICE_NOTIFY_START_PENDING; break;
			case SERVICE_STOP_PENDING: notifyMask &= ~SERVICE_NOTIFY_STOP_PENDING; break;
			case SERVICE_RUNNING: notifyMask &= ~SERVICE_NOTIFY_RUNNING; break;
			case SERVICE_CONTINUE_PENDING: notifyMask &= ~SERVICE_NOTIFY_CONTINUE_PENDING; break;
			case SERVICE_PAUSE_PENDING: notifyMask &= ~SERVICE_NOTIFY_PAUSE_PENDING; break;
			case SERVICE_PAUSED: notifyMask &= ~SERVICE_NOTIFY_PAUSED; break;
			}

			brokerServiceNotification = {};
			brokerServiceNotification.dwVersion = SERVICE_NOTIFY_STATUS_CHANGE;
			brokerServiceNotification.pfnNotifyCallback = BrokerServiceStatusChanged;
			brokerServiceNotificationWindow = window;
			if (NotifyServiceStatusChangeW(brokerStatusServiceHandle, notifyMask,
				&brokerServiceNotification) == ERROR_SUCCESS)
			{
				return true;
			}
			CloseServiceHandle(brokerStatusServiceHandle);
			brokerStatusServiceHandle = nullptr;
			return false;
		}

		void CloseBrokerServiceStatusNotification()
		{
			brokerServiceNotificationWindow = nullptr;
			if (brokerStatusServiceHandle)
			{
				CloseServiceHandle(brokerStatusServiceHandle);
				brokerStatusServiceHandle = nullptr;
			}
		}

		void ScheduleBrokerStatusTimer(HWND window, const BrokerServiceState& serviceState,
			std::uint32_t elevatedProcessCount)
		{
			KillTimer(window, BROKER_STATUS_TIMER);
			const ULONGLONG now = GetTickCount64();
			if (brokerActivationRefreshDeadline != 0 &&
				serviceState.status == BrokerServiceStatus::Running &&
				consecutiveBrokerHealthFailures == 0)
			{
				brokerActivationRefreshDeadline = 0;
			}
			else if (brokerActivationRefreshDeadline > now)
			{
				SetTimer(window, BROKER_STATUS_TIMER,
					BROKER_STATUS_ACTIVATION_INTERVAL, nullptr);
				return;
			}
			else
			{
				brokerActivationRefreshDeadline = 0;
			}
			if (serviceState.status == BrokerServiceStatus::Running)
			{
				SetTimer(window, BROKER_STATUS_TIMER,
					consecutiveBrokerHealthFailures != 0
						? BROKER_STATUS_RETRY_INTERVAL
						: elevatedProcessCount == 0
						? BROKER_STATUS_IDLE_INTERVAL
						: BROKER_STATUS_ACTIVE_INTERVAL,
					nullptr);
			}
			else if (serviceState.status == BrokerServiceStatus::Stopped ||
				serviceState.status == BrokerServiceStatus::Disabled)
			{
				SetTimer(window, BROKER_STATUS_TIMER, BROKER_STATUS_IDLE_INTERVAL, nullptr);
			}
			else
			{
				SetTimer(window, BROKER_STATUS_TIMER, BROKER_STATUS_RETRY_INTERVAL, nullptr);
			}
		}

		std::wstring BuildBrokerStopFailureMessage(
			const broker::PipeBrokerStopResponse& response)
		{
			std::wstring message;
			DWORD error = response.windowsError;
			switch (response.status)
			{
			case broker::PipeBrokerStopStatus::Unavailable:
				message = localization::GetText(localization::TrayTextId::BrokerStopUnavailable);
				break;
			case broker::PipeBrokerStopStatus::IoError:
				message = localization::GetText(localization::TrayTextId::BrokerStopIoFailed);
				break;
			case broker::PipeBrokerStopStatus::InvalidResponse:
				message = localization::GetText(localization::TrayTextId::BrokerStopInvalidResponse);
				break;
			case broker::PipeBrokerStopStatus::Succeeded:
				error = response.result.windowsError;
				if (response.result.status == broker::BrokerStopStatus::InvalidRequest)
					message = localization::GetText(localization::TrayTextId::BrokerStopUnauthorized);
				else
					message = localization::GetText(localization::TrayTextId::BrokerStopFailed);
				break;
			}
			if (error != NO_ERROR)
				message = localization::Format(localization::TextId::BrokerFailureWithError,
					{ message, windows_error::FormatWindowsError(error) });
			return message;
		}

		void UpdateBrokerStatusIcon(HWND window, bool& iconVisible,
			BrokerServiceState& serviceState, std::uint32_t& elevatedProcessCount,
			bool& brokerCommunicationAvailable, broker::ProductVersion& brokerVersion,
			std::vector<broker::TrackedProcessListEntry>& trackedProcesses,
			std::vector<broker::StatusIconListEntry>& statusIcons)
		{
			serviceState = QueryBrokerServiceState();
			if (serviceState.status != BrokerServiceStatus::Running)
			{
				consecutiveBrokerHealthFailures = 0;
				elevatedProcessCount = 0;
				brokerCommunicationAvailable = false;
				brokerVersion = {};
				trackedProcesses.clear();
				statusIcons.clear();
				registeredStatusIconBrokerProcessId = 0;
				statusIconRegistryFailureReported = false;
			}
			else
			{
				const broker::PipeHealthCheck health = broker::QueryBrokerPipeHealth(1000);
				if (health.status == broker::PipeHealthStatus::Succeeded)
				{
					consecutiveBrokerHealthFailures = 0;
					brokerCommunicationAvailable = true;
					brokerVersion = health.brokerVersion;
					elevatedProcessCount = health.elevatedProcessCount;
					trackedProcesses.clear();
					statusIcons.clear();
					broker::StatusIconListRequest iconRequest;
					iconRequest.requestId = broker::GenerateBrokerRequestId();
					iconRequest.clientVersion = {
						VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH, BUILD_NUMBER
					};
					if (iconRequest.requestId != 0)
					{
						const auto iconResponse =
							broker::SubmitStatusIconListRequest(iconRequest, 1000);
						if (iconResponse.status ==
							broker::PipeStatusIconListStatus::Succeeded &&
							iconResponse.result.status ==
							broker::CredentialListStatus::Succeeded)
						{
							statusIcons = iconResponse.result.entries;
							statusIconRegistryFailureReported = false;
							if (registeredStatusIconBrokerProcessId !=
								health.brokerProcessId)
							{
								client_logging::Write(L"Info",
									L"Status icon registered with broker. Broker PID: " +
									std::to_wstring(health.brokerProcessId) +
									L"; same-session status icons: " +
									std::to_wstring(statusIcons.size()) + L".");
								registeredStatusIconBrokerProcessId =
									health.brokerProcessId;
							}
						}
						else if (!statusIconRegistryFailureReported)
						{
							const DWORD error = iconResponse.windowsError != NO_ERROR
								? iconResponse.windowsError
								: iconResponse.result.windowsError;
							client_logging::Write(L"Warning",
								L"Status icon broker registration failed. Pipe status: " +
								std::to_wstring(static_cast<unsigned>(
									iconResponse.status)) +
								L"; result status: " +
								std::to_wstring(static_cast<unsigned>(
									iconResponse.result.status)) +
								L"; error: " + std::to_wstring(error) + L".");
							statusIconRegistryFailureReported = true;
						}
					}
					if (elevatedProcessCount != 0)
					{
						broker::TrackedProcessListRequest request;
						request.requestId = broker::GenerateBrokerRequestId();
						if (request.requestId != 0)
						{
							const auto response = broker::SubmitTrackedProcessListRequest(request, 1000);
							if (response.status == broker::PipeTrackedProcessListStatus::Succeeded &&
								response.result.status == broker::CredentialListStatus::Succeeded)
							{
								trackedProcesses = response.result.entries;
							}
						}
					}
				}
				else
				{
					consecutiveBrokerHealthFailures++;
					if (!brokerCommunicationAvailable ||
						consecutiveBrokerHealthFailures >= BROKER_STATUS_FAILURE_THRESHOLD)
					{
						elevatedProcessCount = 0;
						brokerCommunicationAvailable = false;
						brokerVersion = {};
						trackedProcesses.clear();
						statusIcons.clear();
						registeredStatusIconBrokerProcessId = 0;
					}
				}
			}

			const bool elevatedProcessWindowActive =
				status_menu::HasTrackedProcessWindow(trackedProcesses);
			const bool otherStatusIconAvailable = std::any_of(
				statusIcons.begin(), statusIcons.end(), [](const auto& icon) {
					return icon.processId != GetCurrentProcessId();
				});
			NOTIFYICONDATAW icon = status_icon::Build(window, BROKER_STATUS_CALLBACK,
				serviceState, brokerCommunicationAvailable, elevatedProcessCount,
				elevatedProcessWindowActive, brokerVersion, GetStatusAccount(),
				IsStatusProcessElevated(), otherStatusIconAvailable);
			if (!iconVisible)
			{
				iconVisible = Shell_NotifyIconW(NIM_ADD, &icon) == TRUE;
				if (iconVisible)
				{
					icon.uVersion = NOTIFYICON_VERSION_4;
					Shell_NotifyIconW(NIM_SETVERSION, &icon);
				}
			}
			else
				Shell_NotifyIconW(NIM_MODIFY, &icon);
		}

		LRESULT CALLBACK BrokerStatusWindowProc(HWND window, UINT message,
			WPARAM wParam, LPARAM lParam)
		{
			static bool iconVisible = false;
			static BrokerServiceState serviceState;
			static std::uint32_t elevatedProcessCount = 0;
			static bool brokerCommunicationAvailable = false;
			static broker::ProductVersion brokerVersion;
			static std::vector<broker::TrackedProcessListEntry> trackedProcesses;
			static std::vector<broker::StatusIconListEntry> statusIcons;
			static const UINT taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
			if (message == taskbarCreated)
			{
				iconVisible = false;
				UpdateBrokerStatusIcon(window, iconVisible, serviceState, elevatedProcessCount,
					brokerCommunicationAvailable, brokerVersion, trackedProcesses,
					statusIcons);
				ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
				return 0;
			}
			switch (message)
			{
			case WM_CREATE:
				UpdateBrokerStatusIcon(window, iconVisible, serviceState, elevatedProcessCount,
					brokerCommunicationAvailable, brokerVersion, trackedProcesses, statusIcons);
				ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
				ArmBrokerServiceStatusNotification(window);
				return 0;
			case WM_TIMER:
				if (wParam == BROKER_STATUS_TIMER)
				{
					UpdateBrokerStatusIcon(window, iconVisible, serviceState, elevatedProcessCount,
						brokerCommunicationAvailable, brokerVersion, trackedProcesses, statusIcons);
					ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
				}
				return 0;
			case BROKER_SERVICE_STATUS_CHANGED:
				UpdateBrokerStatusIcon(window, iconVisible, serviceState, elevatedProcessCount,
					brokerCommunicationAvailable, brokerVersion, trackedProcesses, statusIcons);
				ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
				ArmBrokerServiceStatusNotification(window);
				return 0;
			case BROKER_STATUS_LANGUAGE_CHANGED:
				restartStatusIcon = true;
				DestroyWindow(window);
				return 0;
			case BROKER_STATUS_SHOW_MENU:
			{
				POINT cursor = {};
				GetCursorPos(&cursor);
				wParam = MAKEWPARAM(
					static_cast<short>(cursor.x), static_cast<short>(cursor.y));
				lParam = MAKELPARAM(WM_CONTEXTMENU, 0);
				[[fallthrough]];
			}
			case BROKER_STATUS_CALLBACK:
				if (LOWORD(lParam) == WM_CONTEXTMENU)
				{
					UpdateBrokerStatusIcon(window, iconVisible, serviceState, elevatedProcessCount,
						brokerCommunicationAvailable, brokerVersion, trackedProcesses, statusIcons);
					ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
					const status_menu::Model menuModel{
						serviceState,
						brokerCommunicationAvailable,
						elevatedProcessCount,
						&trackedProcesses,
						&statusIcons,
						GetStatusAccount(),
						IsStatusProcessElevated()
					};
					const auto selection = status_menu::Show(window,
						static_cast<short>(LOWORD(wParam)),
						static_cast<short>(HIWORD(wParam)), menuModel);
					if (selection.action == status_actions::Action::Service)
					{
						if (serviceState.status == BrokerServiceStatus::Disabled)
						{
							if (status_actions::LaunchClientCommand(
								window, L"/enable-broker", true))
							{
								// The elevated helper runs asynchronously, so refresh quickly until it finishes.
								brokerActivationRefreshDeadline = GetTickCount64() +
									BROKER_STATUS_ACTIVATION_TIMEOUT;
							}
						}
						else if (serviceState.status == BrokerServiceStatus::Stopped)
						{
							std::uint32_t error = NO_ERROR;
							if (!broker::StartBrokerService(5000, &error))
							{
								const std::wstring details = error == NO_ERROR
									? localization::GetText(localization::TextId::CauseUnknown)
									: localization::Format(localization::TextId::ErrorCode,
										{ windows_error::FormatWindowsError(error) });
								ui::ShowMessageBox(window,
									localization::Format(localization::TextId::BrokerStartFailed,
										{ details }), broker::ProductName,
									MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
							}
						}
						else if (serviceState.status == BrokerServiceStatus::Running)
						{
							broker::BrokerStopRequest request;
							request.requestId = broker::GenerateBrokerRequestId();
							request.action = broker::BrokerServiceControlAction::Disable;
							const auto response = broker::SubmitBrokerStopRequest(request);
							if (response.status != broker::PipeBrokerStopStatus::Succeeded ||
								response.result.status != broker::BrokerStopStatus::Accepted)
							{
								ui::ShowMessageBox(window, BuildBrokerStopFailureMessage(response),
									broker::ProductName,
									MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
							}
							else
							{
								BrokerServiceState finalState;
								if (!WaitForBrokerServiceState(
									BrokerServiceStatus::Disabled, 5000, finalState))
								{
									const std::wstring details = finalState.error == NO_ERROR
										? localization::GetText(localization::TextId::CauseUnknown)
										: localization::Format(localization::TextId::ErrorCode,
											{ windows_error::FormatWindowsError(finalState.error) });
									ui::ShowMessageBox(window,
										localization::Format(
											localization::TrayTextId::BrokerStopIncomplete,
											{ details }), broker::ProductName,
										MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
								}
							}
						}
						UpdateBrokerStatusIcon(window, iconVisible, serviceState,
							elevatedProcessCount, brokerCommunicationAvailable, brokerVersion,
							trackedProcesses, statusIcons);
						ScheduleBrokerStatusTimer(window, serviceState, elevatedProcessCount);
					}
					else if (selection.action == status_actions::Action::Exit)
						DestroyWindow(window);
					else if (selection.action ==
						status_actions::Action::ActivateStatusIcon)
					{
						ActivateStatusIcon(selection.statusIconProcessId);
					}
					else if (selection.action ==
						status_actions::Action::SetLanguageGerman ||
						selection.action ==
						status_actions::Action::SetLanguageEnglish)
					{
						if (status_actions::Execute(window, selection))
						{
							restartStatusIcon = true;
							DestroyWindow(window);
						}
					}
					else
						status_actions::Execute(window, selection);
				}
				return 0;
			case WM_DESTROY:
				KillTimer(window, BROKER_STATUS_TIMER);
				CloseBrokerServiceStatusNotification();
				if (iconVisible)
				{
					NOTIFYICONDATAW icon = {};
					icon.cbSize = sizeof(icon);
					icon.hWnd = window;
					icon.uID = 1;
					Shell_NotifyIconW(NIM_DELETE, &icon);
				}
				PostQuitMessage(0);
				return 0;
			default:
				return DefWindowProcW(window, message, wParam, lParam);
			}
		}
	}

	int RunBrokerStatusIcon(HINSTANCE instance)
	{
		restartStatusIcon = false;
		std::wstring accountSid;
		if (!account_identity::GetCurrentUserSID(accountSid))
		{
			ui::ReportError(localization::GetText(
				localization::TrayTextId::StatusIconIdentityFailed),
				L"Starting the status icon failed because the current account SID "
				L"could not be determined.");
			return 1;
		}

		const std::wstring descriptorText =
			L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;" + accountSid + L")";
		PSECURITY_DESCRIPTOR descriptor = nullptr;
		if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
			descriptorText.c_str(), SDDL_REVISION_1, &descriptor, nullptr))
		{
			const DWORD error = GetLastError();
			ui::ReportError(localization::Format(
				localization::TrayTextId::StatusIconSingletonFailed,
				{ windows_error::FormatWindowsError(error) }),
				L"Creating the status icon mutex security descriptor failed. Windows "
				L"error: " + std::to_wstring(error));
			return 1;
		}
		SECURITY_ATTRIBUTES security = {
			sizeof(security), descriptor, FALSE
		};
		const std::wstring mutexName =
			L"Local\\xucRunBrokerStatus." + accountSid;
		HANDLE mutex = CreateMutexW(&security, TRUE, mutexName.c_str());
		const DWORD mutexError = GetLastError();
		LocalFree(descriptor);
		if (!mutex)
		{
			ui::ReportError(localization::Format(
				localization::TrayTextId::StatusIconSingletonFailed,
				{ windows_error::FormatWindowsError(mutexError) }),
				L"Creating the per-account status icon mutex failed. Windows error: " +
					std::to_wstring(mutexError));
			return 1;
		}
		if (mutexError == ERROR_ALREADY_EXISTS)
		{
			client_logging::Write(L"Info",
				L"A status icon instance is already running for the current account.");
			CloseHandle(mutex);
			return 0;
		}
		std::uint32_t serviceError = NO_ERROR;
		broker::StartBrokerService(5000, &serviceError);
		WNDCLASSEXW windowClass = { sizeof(windowClass) };
		windowClass.lpfnWndProc = BrokerStatusWindowProc;
		windowClass.hInstance = instance;
		windowClass.lpszClassName = BROKER_STATUS_WINDOW_CLASS;
		if (!RegisterClassExW(&windowClass))
		{
			CloseHandle(mutex);
			return 1;
		}
		HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, BROKER_STATUS_WINDOW_CLASS,
			broker::ProductName, WS_OVERLAPPED, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
		if (!window)
		{
			CloseHandle(mutex);
			return 1;
		}
		const std::wstring activationDescriptorText =
			L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x00100002;;;AU)"
			L"S:(ML;;NW;;;ME)";
		PSECURITY_DESCRIPTOR activationDescriptor = nullptr;
		StatusEventRegistration activationRegistration;
		StatusEventRegistration languageChangedRegistration;
		if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
			activationDescriptorText.c_str(), SDDL_REVISION_1,
			&activationDescriptor, nullptr))
		{
			SECURITY_ATTRIBUTES activationSecurity = {
				sizeof(activationSecurity), activationDescriptor, FALSE
			};
			RegisterStatusEvent(
				GetStatusIconActivationEventName(GetCurrentProcessId()),
				StatusIconActivationSignaled, window, activationSecurity,
				L"activation", activationRegistration);
			const std::wstring languageChangedEventName =
				std::wstring(broker::StatusIconLanguageChangedEventNamePrefix) +
				std::to_wstring(GetCurrentProcessId());
			RegisterStatusEvent(languageChangedEventName,
				StatusIconLanguageChanged, window, activationSecurity,
				L"language-change", languageChangedRegistration);
			LocalFree(activationDescriptor);
		}
		else
		{
			client_logging::Write(L"Warning",
				L"Creating the status icon activation security descriptor failed. "
				L"Windows error: " + std::to_wstring(GetLastError()) + L".");
		}
		MSG message = {};
		while (GetMessageW(&message, nullptr, 0, 0) > 0)
		{
			TranslateMessage(&message);
			DispatchMessageW(&message);
		}
		CloseStatusEvent(activationRegistration);
		CloseStatusEvent(languageChangedRegistration);
		CloseHandle(mutex);
		if (restartStatusIcon)
		{
			wchar_t executablePath[MAX_PATH] = {};
			const DWORD pathLength = GetModuleFileNameW(
				nullptr, executablePath, ARRAYSIZE(executablePath));
			if (pathLength == 0 || pathLength >= ARRAYSIZE(executablePath) ||
				reinterpret_cast<INT_PTR>(ShellExecuteW(
					nullptr, L"open", executablePath,
					nullptr, nullptr, SW_HIDE)) <= 32)
			{
				ui::ReportError(localization::Format(
					localization::TextId::CommandLaunchFailed,
					{ L"xucRunTray.exe" }),
					L"Restarting the status icon after the language change failed.");
				return 1;
			}
		}
		return static_cast<int>(message.wParam);
	}
}
