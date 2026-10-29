// Purpose: Builds the tray context menu and maps commands to typed actions.
#include "ClientStatusMenu.h"

#include <ShlObj.h>

#include <algorithm>
#include <string>
#include <utility>
#include <vector>

#include "BrokerPipeClient.h"
#include "ClientLogging.h"
#include "TrayLocalization.h"

namespace
{
	constexpr UINT ExitCommand = 1;
	constexpr UINT ShowCredentialsCommand = 2;
	constexpr UINT DeleteCredentialCommand = 3;
	constexpr UINT ShowApprovalsCommand = 4;
	constexpr UINT ResetApprovalsCommand = 5;
	constexpr UINT RunAuditCommand = 6;
	constexpr UINT ShowHelpCommand = 7;
	constexpr UINT ServiceCommand = 8;
	constexpr UINT CreateCredentialCommand = 9;
	constexpr UINT AdministrativeStatusCommand = 11;
	constexpr UINT SetLanguageGermanCommand = 12;
	constexpr UINT SetLanguageEnglishCommand = 13;
	constexpr UINT SetLanguageAutomaticCommand = 18;
	constexpr UINT ShowLogFileCommand = 14;
	constexpr UINT DeleteLogFileCommand = 15;
	constexpr UINT DeleteAllLogFilesCommand = 16;
	constexpr UINT ShowInfoCommand = 17;
	constexpr UINT StatusIconCommandBase = 500;
	constexpr UINT ProcessCommandBase = 1000;

	struct ProcessWindowEntry
	{
		xucrun::broker::TrackedProcessListEntry process;
		HWND window = nullptr;
	};

	HBITMAP CreateMenuBitmap(HICON icon)
	{
		if (!icon)
			return nullptr;

		const int width = GetSystemMetrics(SM_CXSMICON);
		const int height = GetSystemMetrics(SM_CYSMICON);
		BITMAPINFO bitmapInfo = {};
		bitmapInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
		bitmapInfo.bmiHeader.biWidth = width;
		bitmapInfo.bmiHeader.biHeight = -height;
		bitmapInfo.bmiHeader.biPlanes = 1;
		bitmapInfo.bmiHeader.biBitCount = 32;
		bitmapInfo.bmiHeader.biCompression = BI_RGB;

		HDC screen = GetDC(nullptr);
		void* pixels = nullptr;
		HBITMAP bitmap = screen ? CreateDIBSection(
			screen, &bitmapInfo, DIB_RGB_COLORS, &pixels, nullptr, 0) : nullptr;
		HDC memory = screen && bitmap ? CreateCompatibleDC(screen) : nullptr;
		if (memory)
		{
			HGDIOBJ previousBitmap = SelectObject(memory, bitmap);
			DrawIconEx(memory, 0, 0, icon, width, height, 0, nullptr, DI_NORMAL);
			SelectObject(memory, previousBitmap);
			DeleteDC(memory);
		}
		else if (bitmap)
		{
			DeleteObject(bitmap);
			bitmap = nullptr;
		}
		if (screen)
			ReleaseDC(nullptr, screen);
		return bitmap;
	}

	HBITMAP CreateMenuBitmap(SHSTOCKICONID stockIconId)
	{
		SHSTOCKICONINFO iconInfo = { sizeof(iconInfo) };
		if (FAILED(SHGetStockIconInfo(
			stockIconId, SHGSI_ICON | SHGSI_SMALLICON, &iconInfo)))
		{
			return nullptr;
		}
		HBITMAP bitmap = CreateMenuBitmap(iconInfo.hIcon);
		DestroyIcon(iconInfo.hIcon);
		return bitmap;
	}

	void AppendMenuItemWithIcon(HMENU menu, UINT flags, UINT_PTR command,
		const std::wstring& label, SHSTOCKICONID stockIconId,
		std::vector<HBITMAP>& menuBitmaps)
	{
		if (!AppendMenuW(menu, flags, command, label.c_str()))
			return;
		HBITMAP bitmap = CreateMenuBitmap(stockIconId);
		if (!bitmap)
			return;
		MENUITEMINFOW item = { sizeof(item) };
		item.fMask = MIIM_BITMAP;
		item.hbmpItem = bitmap;
		const int position = GetMenuItemCount(menu) - 1;
		if (position >= 0 &&
			SetMenuItemInfoW(menu, static_cast<UINT>(position), TRUE, &item))
		{
			menuBitmaps.push_back(bitmap);
		}
		else
		{
			DeleteObject(bitmap);
		}
	}

	void AppendMenuItemWithIcon(HMENU menu, UINT flags, UINT_PTR command,
		const std::wstring& label, HICON icon, std::vector<HBITMAP>& menuBitmaps)
	{
		if (!AppendMenuW(menu, flags, command, label.c_str()))
			return;
		HBITMAP bitmap = CreateMenuBitmap(icon);
		if (!bitmap)
			return;
		MENUITEMINFOW item = { sizeof(item) };
		item.fMask = MIIM_BITMAP;
		item.hbmpItem = bitmap;
		const int position = GetMenuItemCount(menu) - 1;
		if (position >= 0 &&
			SetMenuItemInfoW(menu, static_cast<UINT>(position), TRUE, &item))
		{
			menuBitmaps.push_back(bitmap);
		}
		else
		{
			DeleteObject(bitmap);
		}
	}

	HICON LoadProcessIcon(std::uint32_t processId)
	{
		HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
		if (!process)
			return nullptr;
		std::wstring imagePath(32768, L'\0');
		DWORD imagePathLength = static_cast<DWORD>(imagePath.size());
		const bool pathAvailable = QueryFullProcessImageNameW(
			process, 0, imagePath.data(), &imagePathLength) != FALSE;
		CloseHandle(process);
		if (!pathAvailable)
			return nullptr;
		imagePath.resize(imagePathLength);

		SHFILEINFOW fileInfo = {};
		if (!SHGetFileInfoW(imagePath.c_str(), 0, &fileInfo, sizeof(fileInfo),
			SHGFI_ICON | SHGFI_SMALLICON))
		{
			return nullptr;
		}
		return fileInfo.hIcon;
	}

	HICON LoadWindowIcon(HWND window, std::uint32_t processId)
	{
		for (const WPARAM iconType : { ICON_SMALL2, ICON_SMALL, ICON_BIG })
		{
			DWORD_PTR icon = 0;
			if (SendMessageTimeoutW(window, WM_GETICON, iconType, 0,
				SMTO_ABORTIFHUNG, 100, &icon) != 0 && icon != 0)
			{
				HICON copy = CopyIcon(reinterpret_cast<HICON>(icon));
				if (copy)
					return copy;
			}
		}
		return LoadProcessIcon(processId);
	}

	BOOL CALLBACK CollectTrackedProcessWindows(HWND candidate, LPARAM parameter)
	{
		auto* context = reinterpret_cast<std::pair<DWORD, std::vector<HWND>*>*>(parameter);
		DWORD processId = 0;
		GetWindowThreadProcessId(candidate, &processId);
		if (processId == context->first && IsWindowVisible(candidate) &&
			GetWindow(candidate, GW_OWNER) == nullptr &&
			(GetWindowLongPtrW(candidate, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) == 0)
		{
			context->second->push_back(candidate);
		}
		return TRUE;
	}

	struct TrackedProcessWindowSearchContext
	{
		const std::vector<xucrun::broker::TrackedProcessListEntry>* processes = nullptr;
		bool found = false;
	};

	BOOL CALLBACK FindTrackedProcessWindow(HWND candidate, LPARAM parameter)
	{
		if (!IsWindowVisible(candidate) || GetWindow(candidate, GW_OWNER) != nullptr ||
			(GetWindowLongPtrW(candidate, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0)
		{
			return TRUE;
		}
		DWORD processId = 0;
		GetWindowThreadProcessId(candidate, &processId);
		auto* context = reinterpret_cast<TrackedProcessWindowSearchContext*>(parameter);
		context->found = std::any_of(
			context->processes->begin(), context->processes->end(),
			[processId](const auto& process) { return process.processId == processId; });
		return context->found ? FALSE : TRUE;
	}

	std::vector<HWND> GetTrackedProcessWindows(DWORD processId)
	{
		std::vector<HWND> windows;
		std::pair<DWORD, std::vector<HWND>*> context{ processId, &windows };
		EnumWindows(CollectTrackedProcessWindows, reinterpret_cast<LPARAM>(&context));
		return windows;
	}

	std::wstring GetTrackedWindowMenuText(HWND window, const std::wstring& fallback)
	{
		const int length = GetWindowTextLengthW(window);
		if (length <= 0)
			return fallback;
		std::vector<wchar_t> title(static_cast<size_t>(length) + 1);
		if (GetWindowTextW(window, title.data(), static_cast<int>(title.size())) <= 0)
			return fallback;
		std::wstring result(title.data());
		return result.size() > 80 ? result.substr(0, 77) + L"..." : result;
	}

	bool TryGetCredentialCount(std::size_t& count)
	{
		xucrun::broker::CredentialListRequest request;
		request.requestId = xucrun::broker::GenerateBrokerRequestId();
		if (request.requestId == 0)
			return false;
		const auto response = xucrun::broker::SubmitCredentialListRequest(request);
		if (response.status != xucrun::broker::PipeCredentialListStatus::Succeeded ||
			response.result.status != xucrun::broker::CredentialListStatus::Succeeded)
		{
			return false;
		}
		count = response.result.entries.size();
		return true;
	}

	bool TryGetApprovalCount(std::size_t& count)
	{
		xucrun::broker::ApprovalListRequest request;
		request.requestId = xucrun::broker::GenerateBrokerRequestId();
		if (request.requestId == 0)
			return false;
		const auto response = xucrun::broker::SubmitApprovalListRequest(request);
		if (response.status != xucrun::broker::PipeApprovalManagementStatus::Succeeded ||
			response.result.status != xucrun::broker::ApprovalManagementStatus::Succeeded)
		{
			return false;
		}
		count = response.result.entries.size();
		return true;
	}

	xucrun::status_actions::Action MapCommand(UINT command)
	{
		using xucrun::status_actions::Action;
		switch (command)
		{
		case CreateCredentialCommand: return Action::CreateCredential;
		case ShowCredentialsCommand: return Action::ShowCredentials;
		case DeleteCredentialCommand: return Action::DeleteCredential;
		case ShowApprovalsCommand: return Action::ShowApprovals;
		case ResetApprovalsCommand: return Action::ResetApprovals;
		case AdministrativeStatusCommand: return Action::AdministrativeStatus;
		case RunAuditCommand: return Action::RunAudit;
		case ShowHelpCommand: return Action::ShowHelp;
		case ShowLogFileCommand: return Action::ShowLogFile;
		case DeleteLogFileCommand: return Action::DeleteLogFile;
		case DeleteAllLogFilesCommand: return Action::DeleteAllLogFiles;
		case ShowInfoCommand: return Action::ShowInfo;
		case SetLanguageGermanCommand: return Action::SetLanguageGerman;
		case SetLanguageEnglishCommand: return Action::SetLanguageEnglish;
		case SetLanguageAutomaticCommand: return Action::SetLanguageAutomatic;
		case ServiceCommand: return Action::Service;
		case ExitCommand: return Action::Exit;
		default: return Action::None;
		}
	}
}

namespace xucrun::status_menu
{
	bool HasTrackedProcessWindow(
		const std::vector<broker::TrackedProcessListEntry>& trackedProcesses)
	{
		TrackedProcessWindowSearchContext context{ &trackedProcesses, false };
		EnumWindows(FindTrackedProcessWindow, reinterpret_cast<LPARAM>(&context));
		return context.found;
	}

	status_actions::Selection Show(HWND owner, int x, int y, const Model& model)
	{
		status_actions::Selection selection;
		HMENU menu = CreatePopupMenu();
		if (!menu)
			return selection;

		std::vector<HBITMAP> menuBitmaps;
		std::vector<std::uint32_t> statusIconProcessIds;
		const bool otherStatusIconAvailable = model.statusIcons &&
			std::any_of(model.statusIcons->begin(), model.statusIcons->end(),
				[](const auto& icon) {
					return icon.processId != GetCurrentProcessId();
				});
		if (otherStatusIconAvailable)
		{
			const std::wstring statusContext = localization::Format(
				localization::TrayTextId::TooltipStatusFor,
				{ model.currentAccount,
					localization::GetText(model.currentProcessElevated
						? localization::TextId::InfoElevated
						: localization::TextId::InfoNotElevated) });
			AppendMenuW(menu, MF_STRING | MF_GRAYED | MF_CHECKED,
				0, statusContext.c_str());
			SetMenuDefaultItem(menu, 0, TRUE);
			for (const auto& icon : *model.statusIcons)
			{
				if (icon.processId == GetCurrentProcessId())
					continue;
				const std::wstring peerContext = localization::Format(
					localization::TrayTextId::TooltipStatusFor,
					{ icon.canonicalAccountName,
						localization::GetText(icon.elevated
							? localization::TextId::InfoElevated
							: localization::TextId::InfoNotElevated) }) +
					L" - PID " + std::to_wstring(icon.processId) + L", v" +
					std::to_wstring(icon.clientVersion.major) + L"." +
					std::to_wstring(icon.clientVersion.minor) + L"." +
					std::to_wstring(icon.clientVersion.patch) + L"." +
					std::to_wstring(icon.clientVersion.build);
				const UINT commandId = StatusIconCommandBase +
					static_cast<UINT>(statusIconProcessIds.size());
				statusIconProcessIds.push_back(icon.processId);
				AppendMenuW(menu, MF_STRING, commandId, peerContext.c_str());
			}
			AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
		}
		const UINT brokerCommandFlags = model.brokerCommunicationAvailable
			? MF_STRING : MF_STRING | MF_GRAYED;
		std::size_t credentialCount = 0;
		std::size_t approvalCount = 0;
		const bool credentialCountAvailable = model.brokerCommunicationAvailable &&
			TryGetCredentialCount(credentialCount);
		const bool approvalCountAvailable = model.brokerCommunicationAvailable &&
			TryGetApprovalCount(approvalCount);
		const bool administrativeStatusAvailable = model.brokerCommunicationAvailable;
		const std::wstring unavailable = localization::GetText(
			localization::TextId::ValueNotAvailable);
		const std::wstring credentialMenuLabel = localization::Format(
			localization::TrayTextId::MenuShowCredentials,
			{ credentialCountAvailable ? std::to_wstring(credentialCount) : unavailable });
		const std::wstring approvalMenuLabel = localization::Format(
			localization::TrayTextId::MenuShowApprovals,
			{ approvalCountAvailable ? std::to_wstring(approvalCount) : unavailable });
		std::vector<ProcessWindowEntry> windowEntries;

		static const std::vector<broker::TrackedProcessListEntry> emptyTrackedProcesses;
		const auto& trackedProcesses = model.trackedProcesses
			? *model.trackedProcesses : emptyTrackedProcesses;
		if (!trackedProcesses.empty())
		{
			HMENU processMenu = CreatePopupMenu();
			if (processMenu)
			{
				std::vector<std::pair<broker::TrackedProcessListEntry,
					std::vector<HWND>>> processEntries;
				processEntries.reserve(trackedProcesses.size());
				for (const auto& process : trackedProcesses)
					processEntries.emplace_back(
						process, GetTrackedProcessWindows(process.processId));
				std::stable_partition(processEntries.begin(), processEntries.end(),
					[](const auto& entry) { return !entry.second.empty(); });
				constexpr std::size_t MaximumDisplayedProcessEntries = 32;
				if (processEntries.size() > MaximumDisplayedProcessEntries)
					processEntries.resize(MaximumDisplayedProcessEntries);
				const bool candidateListTruncated = model.elevatedProcessCount >
					broker::MaximumTrackedProcessEntries;
				const bool processListTruncated =
					processEntries.size() < model.elevatedProcessCount;
				if (candidateListTruncated)
				{
					const std::wstring label = localization::Format(
						localization::TrayTextId::CandidateSelectionLimited,
						{ std::to_wstring(broker::MaximumTrackedProcessEntries),
							std::to_wstring(model.elevatedProcessCount) });
					AppendMenuW(processMenu, MF_STRING | MF_DISABLED, 0, label.c_str());
				}
				if (processListTruncated)
				{
					const std::wstring label = localization::Format(
						localization::TrayTextId::ProcessListTruncated,
						{ std::to_wstring(processEntries.size()),
							std::to_wstring(model.elevatedProcessCount) });
					AppendMenuW(processMenu, MF_STRING | MF_DISABLED, 0, label.c_str());
				}
				if (candidateListTruncated || processListTruncated)
					AppendMenuW(processMenu, MF_SEPARATOR, 0, nullptr);
				for (const auto& [process, processWindows] : processEntries)
				{
					const std::wstring processRole =
						process.processId == GetCurrentProcessId()
						? localization::GetText(localization::TrayTextId::IconProcessRole) : L"";
					const std::wstring processLabel = process.processBaseName + processRole +
						L" (PID " + std::to_wstring(process.processId) + L")";
					if (processWindows.empty())
					{
						AppendMenuW(processMenu, MF_STRING | MF_DISABLED, 0,
							(processLabel + L" - " + localization::GetText(
								localization::TrayTextId::NoWindow)).c_str());
					}
					else if (processWindows.size() == 1)
					{
						HICON processIcon = LoadWindowIcon(
							processWindows.front(), process.processId);
						const UINT commandId = ProcessCommandBase +
							static_cast<UINT>(windowEntries.size());
						windowEntries.push_back({ process, processWindows.front() });
						const std::wstring windowLabel = processLabel + L" - " +
							GetTrackedWindowMenuText(processWindows.front(),
								localization::GetText(localization::TrayTextId::WindowFallback));
						AppendMenuItemWithIcon(processMenu, MF_STRING, commandId,
							windowLabel, processIcon, menuBitmaps);
						if (processIcon)
							DestroyIcon(processIcon);
					}
					else
					{
						HMENU windowMenu = CreatePopupMenu();
						if (!windowMenu)
							continue;
						HICON processIcon = LoadWindowIcon(
							processWindows.front(), process.processId);
						for (HWND processWindow : processWindows)
						{
							const UINT commandId = ProcessCommandBase +
								static_cast<UINT>(windowEntries.size());
							windowEntries.push_back({ process, processWindow });
							HICON windowIcon = LoadWindowIcon(
								processWindow, process.processId);
							AppendMenuItemWithIcon(windowMenu, MF_STRING, commandId,
								GetTrackedWindowMenuText(processWindow, process.processBaseName),
								windowIcon, menuBitmaps);
							if (windowIcon)
								DestroyIcon(windowIcon);
						}
						AppendMenuItemWithIcon(processMenu, MF_POPUP,
							reinterpret_cast<UINT_PTR>(windowMenu), processLabel,
							processIcon, menuBitmaps);
						if (processIcon)
							DestroyIcon(processIcon);
					}
				}
				const std::wstring processMenuLabel = localization::Format(
					localization::TrayTextId::ElevatedProcesses,
					{ std::to_wstring(model.elevatedProcessCount) });
				AppendMenuItemWithIcon(menu, MF_POPUP,
					reinterpret_cast<UINT_PTR>(processMenu), processMenuLabel,
					SIID_APPLICATION, menuBitmaps);
				AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
			}
		}

		AppendMenuItemWithIcon(menu, brokerCommandFlags, CreateCredentialCommand,
			localization::GetText(localization::TrayTextId::MenuCreateCredential),
			SIID_KEY, menuBitmaps);
		AppendMenuItemWithIcon(menu,
			credentialCountAvailable ? MF_STRING : MF_STRING | MF_GRAYED,
			ShowCredentialsCommand, credentialMenuLabel, SIID_LOCK, menuBitmaps);
		AppendMenuItemWithIcon(menu, brokerCommandFlags, DeleteCredentialCommand,
			localization::GetText(localization::TrayTextId::MenuDeleteCredential),
			SIID_DELETE, menuBitmaps);
		AppendMenuItemWithIcon(menu,
			approvalCountAvailable ? MF_STRING : MF_STRING | MF_GRAYED,
			ShowApprovalsCommand, approvalMenuLabel, SIID_SHIELD, menuBitmaps);
		AppendMenuItemWithIcon(menu, brokerCommandFlags, ResetApprovalsCommand,
			localization::GetText(localization::TrayTextId::MenuResetApprovals),
			SIID_RENAME, menuBitmaps);
		AppendMenuItemWithIcon(menu,
			administrativeStatusAvailable ? MF_STRING : MF_STRING | MF_GRAYED,
			AdministrativeStatusCommand,
			localization::GetText(localization::TrayTextId::MenuAdministrativeStatus),
			SIID_USERS, menuBitmaps);
		AppendMenuItemWithIcon(menu, brokerCommandFlags, RunAuditCommand,
			localization::GetText(localization::TrayTextId::MenuRunSecurityAudit),
			SIID_WARNING, menuBitmaps);
		HMENU logFileMenu = CreatePopupMenu();
		if (logFileMenu)
		{
			std::wstring currentLogFilePath;
			const UINT currentLogFileFlags =
				client_logging::TryGetExistingLogFilePath(currentLogFilePath)
				? MF_STRING : MF_STRING | MF_GRAYED;
			std::wstring logDirectory;
			std::vector<std::wstring> logFiles;
			DWORD logFileQueryError = ERROR_SUCCESS;
			const bool logFilesAvailable = client_logging::GetExistingLogFiles(
				logDirectory, logFiles, logFileQueryError) && !logFiles.empty();
			AppendMenuW(logFileMenu, currentLogFileFlags, ShowLogFileCommand,
				localization::GetText(
					localization::TrayTextId::MenuShowLogFile).c_str());
			AppendMenuW(logFileMenu, currentLogFileFlags, DeleteLogFileCommand,
				localization::GetText(
					localization::TrayTextId::MenuDeleteLogFile).c_str());
			AppendMenuW(logFileMenu, MF_SEPARATOR, 0, nullptr);
			AppendMenuW(logFileMenu,
				logFilesAvailable ? MF_STRING : MF_STRING | MF_GRAYED,
				DeleteAllLogFilesCommand,
				localization::GetText(
					localization::TrayTextId::MenuDeleteAllLogFiles).c_str());
			AppendMenuItemWithIcon(menu, MF_POPUP,
				reinterpret_cast<UINT_PTR>(logFileMenu),
				localization::GetText(localization::TrayTextId::MenuLogFiles),
				SIID_DOCNOASSOC, menuBitmaps);
		}
		HMENU languageMenu = CreatePopupMenu();
		if (languageMenu)
		{
			const bool usesAutomatic =
				localization::UsesAutomaticLanguage();
			const bool usesGerman = localization::UsesGermanResources();
			AppendMenuW(languageMenu,
				MF_STRING | (usesAutomatic ? MF_CHECKED | MF_GRAYED : MF_UNCHECKED),
				SetLanguageAutomaticCommand,
				localization::GetText(
					localization::TrayTextId::MenuLanguageAutomatic).c_str());
			AppendMenuW(languageMenu,
				MF_STRING | (!usesAutomatic && usesGerman
					? MF_CHECKED | MF_GRAYED : MF_UNCHECKED),
				SetLanguageGermanCommand,
				localization::GetText(
					localization::TrayTextId::MenuLanguageGerman).c_str());
			AppendMenuW(languageMenu,
				MF_STRING | (!usesAutomatic && !usesGerman
					? MF_CHECKED | MF_GRAYED : MF_UNCHECKED),
				SetLanguageEnglishCommand,
				localization::GetText(
					localization::TrayTextId::MenuLanguageEnglish).c_str());
			AppendMenuItemWithIcon(menu, MF_POPUP,
				reinterpret_cast<UINT_PTR>(languageMenu),
				localization::GetText(localization::TrayTextId::MenuLanguage),
				SIID_APPLICATION, menuBitmaps);
		}
		AppendMenuItemWithIcon(menu, brokerCommandFlags, ShowHelpCommand,
			localization::GetText(localization::TrayTextId::MenuShowHelp),
			SIID_HELP, menuBitmaps);
		AppendMenuItemWithIcon(menu, MF_STRING, ShowInfoCommand,
			localization::GetText(localization::TrayTextId::MenuShowInfo),
			SIID_INFO, menuBitmaps);
		AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

		using status_icon::BrokerServiceStatus;
		if (model.serviceState.status == BrokerServiceStatus::Running)
			AppendMenuItemWithIcon(menu,
				model.brokerCommunicationAvailable ? MF_STRING : MF_GRAYED,
				ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuDisableService),
				SIID_ERROR, menuBitmaps);
		else if (model.serviceState.status == BrokerServiceStatus::Disabled)
			AppendMenuItemWithIcon(menu, MF_STRING, ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuEnableService),
				SIID_SHIELD, menuBitmaps);
		else if (model.serviceState.status == BrokerServiceStatus::Stopped)
			AppendMenuItemWithIcon(menu, MF_STRING, ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuStartService),
				SIID_INFO, menuBitmaps);
		else if (model.serviceState.status == BrokerServiceStatus::Starting)
			AppendMenuItemWithIcon(menu, MF_STRING | MF_GRAYED, ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuServiceStarting),
				SIID_INFO, menuBitmaps);
		else if (model.serviceState.status == BrokerServiceStatus::Stopping)
			AppendMenuItemWithIcon(menu, MF_STRING | MF_GRAYED, ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuServiceStopping),
				SIID_ERROR, menuBitmaps);
		else
			AppendMenuItemWithIcon(menu, MF_STRING | MF_GRAYED, ServiceCommand,
				localization::GetText(localization::TrayTextId::MenuServiceUnavailable),
				SIID_ERROR, menuBitmaps);
		AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
		AppendMenuItemWithIcon(menu, MF_STRING, ExitCommand,
			localization::GetText(localization::TrayTextId::MenuExitStatus),
			SIID_DELETE, menuBitmaps);

		SetForegroundWindow(owner);
		const UINT command = TrackPopupMenu(menu,
			TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
			x, y, 0, owner, nullptr);
		DestroyMenu(menu);
		for (HBITMAP bitmap : menuBitmaps)
			DeleteObject(bitmap);

		if (command >= ProcessCommandBase)
		{
			const size_t index = command - ProcessCommandBase;
			if (index < windowEntries.size())
			{
				selection.action = status_actions::Action::ActivateProcessWindow;
				selection.process = windowEntries[index].process;
				selection.processWindow = windowEntries[index].window;
			}
			return selection;
		}
		if (command >= StatusIconCommandBase)
		{
			const size_t index = command - StatusIconCommandBase;
			if (index < statusIconProcessIds.size())
			{
				selection.action = status_actions::Action::ActivateStatusIcon;
				selection.statusIconProcessId = statusIconProcessIds[index];
			}
			return selection;
		}
		selection.action = MapCommand(command);
		return selection;
	}
}
