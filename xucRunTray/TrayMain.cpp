// Purpose: Runs the optional xucRun status and convenience interface as a separate process.
#include <Windows.h>

#include <string>
#include <vector>

#include "BuildVersion.h"
#include "BrokerPipeClient.h"
#include "ClientAccountIdentity.h"
#include "TrayBrokerStatus.h"
#include "ClientLogging.h"
#include "ClientUiCommon.h"
#include "ClientWindowsError.h"
#include "Localization.h"

#define XUCRUN_WIDEN_DETAIL(value) L##value
#define XUCRUN_WIDEN(value) XUCRUN_WIDEN_DETAIL(value)

namespace
{
	std::wstring TrimCommandLineWhitespace(const wchar_t* commandLine)
	{
		const std::wstring value = commandLine ? commandLine : L"";
		const std::size_t first = value.find_first_not_of(L" \t\r\n");
		if (first == std::wstring::npos)
			return {};
		const std::size_t last = value.find_last_not_of(L" \t\r\n");
		return value.substr(first, last - first + 1);
	}

	int RunBrokerPolicyIntegrationTest()
	{
		xucrun::broker::AdministrativeInventoryRequest request;
		xucrun::broker::PipeAdministrativeInventoryResponse response;
		for (int attempt = 0; attempt < 5; ++attempt)
		{
			request.requestId = xucrun::broker::GenerateBrokerRequestId();
			if (request.requestId == 0)
				return 2;
			response =
				xucrun::broker::SubmitAdministrativeInventoryRequest(request, 1000);
			if (response.status ==
				xucrun::broker::PipeAdministrativeInventoryStatus::Succeeded)
			{
				return 3;
			}
			if (response.status ==
				xucrun::broker::PipeAdministrativeInventoryStatus::PolicyDenied)
			{
				return response.windowsError == ERROR_ACCESS_DENIED ? 0 : 6;
			}
			if (response.status ==
				xucrun::broker::PipeAdministrativeInventoryStatus::InvalidResponse)
			{
				return 4;
			}
			Sleep(100);
		}
		const int statusPrefix = response.status ==
			xucrun::broker::PipeAdministrativeInventoryStatus::Unavailable
			? 0x10000000 : 0x20000000;
		return statusPrefix |
			static_cast<int>(response.windowsError & 0x0000FFFF);
	}

	std::vector<std::wstring> ApplyEarlyProcessHardening()
	{
		std::vector<std::wstring> warnings;
		auto recordFailure = [&warnings](const wchar_t* mitigation) {
			warnings.push_back(std::wstring(mitigation) +
				L" could not be enabled (error " +
				xucrun::windows_error::FormatWindowsError(GetLastError()) + L")");
		};
		if (!SetDefaultDllDirectories(
			LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_USER_DIRS))
			recordFailure(L"Restricted DLL search");

		PROCESS_MITIGATION_DYNAMIC_CODE_POLICY dynamicCodePolicy = {};
		dynamicCodePolicy.ProhibitDynamicCode = 1;
		if (!SetProcessMitigationPolicy(ProcessDynamicCodePolicy,
			&dynamicCodePolicy, sizeof(dynamicCodePolicy)))
			recordFailure(L"Prohibit dynamic code generation");

		PROCESS_MITIGATION_EXTENSION_POINT_DISABLE_POLICY extensionPointPolicy = {};
		extensionPointPolicy.DisableExtensionPoints = 1;
		if (!SetProcessMitigationPolicy(ProcessExtensionPointDisablePolicy,
			&extensionPointPolicy, sizeof(extensionPointPolicy)))
			recordFailure(L"Disable legacy extension points");

		PROCESS_MITIGATION_IMAGE_LOAD_POLICY imageLoadPolicy = {};
		imageLoadPolicy.NoRemoteImages = 1;
		imageLoadPolicy.NoLowMandatoryLabelImages = 1;
		imageLoadPolicy.PreferSystem32Images = 1;
		if (!SetProcessMitigationPolicy(ProcessImageLoadPolicy,
			&imageLoadPolicy, sizeof(imageLoadPolicy)))
			recordFailure(L"Restricted image loading");
		return warnings;
	}
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR commandLine, int)
{
	const std::wstring normalizedCommandLine =
		TrimCommandLineWhitespace(commandLine);
	if (_wcsicmp(normalizedCommandLine.c_str(), L"/broker-policy-test") == 0)
	{
		return RunBrokerPolicyIntegrationTest();
	}

	std::wstring localizationError;
	if (!xucrun::localization::Initialize(localizationError,
		xucrun::localization::Component::Tray))
	{
		xucrun::ui::ShowMessageBox(nullptr, localizationError,
			L"xucRun Tray - Localization error", MB_OK | MB_ICONERROR);
		return ERROR_RESOURCE_LANG_NOT_FOUND;
	}
	const std::vector<std::wstring> hardeningWarnings =
		ApplyEarlyProcessHardening();

	std::wstring configuredLogDirectory;
	std::wstring failedLogDirectory;
	std::wstring configurationPath;
	DWORD logError = NO_ERROR;
	if (!xucrun::client_logging::Initialize(configuredLogDirectory,
		failedLogDirectory, configurationPath, logError))
	{
		xucrun::ui::ReportWarning(xucrun::localization::Format(
			xucrun::localization::TextId::ClientLogInitializationFailed,
			{ configuredLogDirectory, failedLogDirectory, configurationPath,
				xucrun::windows_error::FormatWindowsError(logError) }),
			L"Tray file logging initialization failed. Windows error: " +
				std::to_wstring(logError));
	}
	for (const std::wstring& warning : hardeningWarnings)
		xucrun::client_logging::Write(L"Warning", warning);

	std::wstring userName;
	std::wstring domain;
	const std::wstring account =
		xucrun::account_identity::GetCurrentUserInfo(userName, domain)
		? domain.empty() ? userName : domain + L"\\" + userName
		: L"unavailable";
	xucrun::client_logging::Write(L"Info",
		L"xucRun process started. Mode: status icon tray process (xucRunTray.exe); "
		L"Account: " + account + L"; Elevated: " +
		(xucrun::account_identity::IsRunningAsAdministrator()
			? L"true" : L"false") +
		L"; build from " XUCRUN_WIDEN(BUILD_DATE) L" "
		XUCRUN_WIDEN(BUILD_TIME));
	return xucrun::broker_status::RunBrokerStatusIcon(instance);
}
