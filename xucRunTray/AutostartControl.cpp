// Purpose: Implements secure per-user autostart discovery and maintenance for xucRun Tray.
// Approach: Validates and changes the non-elevated per-user logon task created by the public Tray installer.
#include "AutostartControl.h"

#include <shellapi.h>
#include <taskschd.h>
#include <wrl/client.h>

#include <string>
#include <vector>

#include "ClientAccountIdentity.h"
#include "BrokerPipeClient.h"
#include "ClientUiCommon.h"
#include "ClientWindowsError.h"
#include "TrayLocalization.h"

namespace
{
	using Microsoft::WRL::ComPtr;

	constexpr wchar_t TaskFolder[] = L"\\xucRun";
	constexpr wchar_t TaskPrefix[] = L"BrokerStatus-";
	constexpr wchar_t StandaloneScript[] = L"Install-xucRunTray.ps1";
	constexpr wchar_t TrayUninstallRegistryPath[] =
		L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\xucRun Tray";

	bool GetModulePath(std::wstring& path)
	{
		std::vector<wchar_t> buffer(512);
		for (;;)
		{
			const DWORD length = GetModuleFileNameW(
				nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
			if (length == 0)
				return false;
			if (length < buffer.size() - 1)
			{
				path.assign(buffer.data(), length);
				return true;
			}
			buffer.resize(buffer.size() * 2);
		}
	}

	bool GetSiblingPath(const wchar_t* name, std::wstring& path)
	{
		if (!GetModulePath(path))
			return false;
		const std::size_t separator = path.find_last_of(L"\\/");
		if (separator == std::wstring::npos)
			return false;
		path.replace(separator + 1, std::wstring::npos, name);
		return true;
	}

	bool IsRegularFile(const std::wstring& path)
	{
		const DWORD attributes = GetFileAttributesW(path.c_str());
		return attributes != INVALID_FILE_ATTRIBUTES &&
			(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) == 0;
	}

	bool GetInstalledMaintenanceScript(std::wstring& scriptPath)
	{
		if (!GetSiblingPath(StandaloneScript, scriptPath))
			return false;

		HKEY uninstallKey = nullptr;
		const LONG registrationResult = RegOpenKeyExW(HKEY_LOCAL_MACHINE,
			TrayUninstallRegistryPath, 0, KEY_READ, &uninstallKey);
		if (uninstallKey)
			RegCloseKey(uninstallKey);
		return registrationResult == ERROR_SUCCESS &&
			IsRegularFile(scriptPath);
	}

	bool EqualsAndFree(BSTR value, const std::wstring& expected)
	{
		const bool equal = value &&
			_wcsicmp(value, expected.c_str()) == 0;
		SysFreeString(value);
		return equal;
	}

	bool IdentityMatchesAndFree(BSTR value, const std::wstring& expectedSid)
	{
		if (!value)
			return false;
		const std::wstring identity(value);
		SysFreeString(value);
		if (_wcsicmp(identity.c_str(), expectedSid.c_str()) == 0)
			return true;
		std::wstring canonicalName;
		std::wstring resolvedSid;
		return xucrun::account_identity::ResolveAccountIdentity(
			identity, canonicalName, resolvedSid) &&
			_wcsicmp(resolvedSid.c_str(), expectedSid.c_str()) == 0;
	}

	bool IsMissingTask(HRESULT result)
	{
		return result == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND) ||
			result == HRESULT_FROM_WIN32(ERROR_PATH_NOT_FOUND);
	}

	xucrun::autostart::Status ValidateScheduledTask(
		ITaskService* service, const std::wstring& sid,
		const std::wstring& executablePath)
	{
		BSTR folderPath = SysAllocString(TaskFolder);
		ComPtr<ITaskFolder> folder;
		const HRESULT folderResult = service->GetFolder(folderPath, &folder);
		SysFreeString(folderPath);
		if (FAILED(folderResult))
			return IsMissingTask(folderResult)
				? xucrun::autostart::Status::Disabled
				: xucrun::autostart::Status::Unavailable;

		const std::wstring taskName = std::wstring(TaskPrefix) + sid;
		BSTR taskNameValue = SysAllocString(taskName.c_str());
		ComPtr<IRegisteredTask> task;
		const HRESULT taskResult = folder->GetTask(taskNameValue, &task);
		SysFreeString(taskNameValue);
		if (FAILED(taskResult))
			return IsMissingTask(taskResult)
				? xucrun::autostart::Status::Disabled
				: xucrun::autostart::Status::Unavailable;

		VARIANT_BOOL enabled = VARIANT_FALSE;
		if (FAILED(task->get_Enabled(&enabled)) || enabled != VARIANT_TRUE)
			return xucrun::autostart::Status::Disabled;

		ComPtr<ITaskDefinition> definition;
		if (FAILED(task->get_Definition(&definition)))
			return xucrun::autostart::Status::Unavailable;

		ComPtr<IPrincipal> principal;
		BSTR principalUser = nullptr;
		TASK_LOGON_TYPE logonType = TASK_LOGON_NONE;
		TASK_RUNLEVEL_TYPE runLevel = TASK_RUNLEVEL_HIGHEST;
		if (FAILED(definition->get_Principal(&principal)) ||
			FAILED(principal->get_UserId(&principalUser)) ||
		!IdentityMatchesAndFree(principalUser, sid) ||
			FAILED(principal->get_LogonType(&logonType)) ||
			logonType != TASK_LOGON_INTERACTIVE_TOKEN ||
			FAILED(principal->get_RunLevel(&runLevel)) ||
			runLevel != TASK_RUNLEVEL_LUA)
		{
			return xucrun::autostart::Status::Disabled;
		}

		ComPtr<ITriggerCollection> triggers;
		LONG triggerCount = 0;
		if (FAILED(definition->get_Triggers(&triggers)) ||
			FAILED(triggers->get_Count(&triggerCount)) || triggerCount != 1)
		{
			return xucrun::autostart::Status::Disabled;
		}
		ComPtr<ITrigger> trigger;
		if (FAILED(triggers->get_Item(1, &trigger)))
			return xucrun::autostart::Status::Unavailable;
		TASK_TRIGGER_TYPE2 triggerType = TASK_TRIGGER_EVENT;
		VARIANT_BOOL triggerEnabled = VARIANT_FALSE;
		if (FAILED(trigger->get_Type(&triggerType)) ||
			triggerType != TASK_TRIGGER_LOGON ||
			FAILED(trigger->get_Enabled(&triggerEnabled)) ||
			triggerEnabled != VARIANT_TRUE)
		{
			return xucrun::autostart::Status::Disabled;
		}
		ComPtr<ILogonTrigger> logonTrigger;
		BSTR triggerUser = nullptr;
		if (FAILED(trigger.As(&logonTrigger)) ||
			FAILED(logonTrigger->get_UserId(&triggerUser)) ||
			!IdentityMatchesAndFree(triggerUser, sid))
		{
			return xucrun::autostart::Status::Disabled;
		}

		ComPtr<IActionCollection> actions;
		LONG actionCount = 0;
		if (FAILED(definition->get_Actions(&actions)) ||
			FAILED(actions->get_Count(&actionCount)) || actionCount != 1)
		{
			return xucrun::autostart::Status::Disabled;
		}
		ComPtr<IAction> action;
		TASK_ACTION_TYPE actionType = TASK_ACTION_COM_HANDLER;
		if (FAILED(actions->get_Item(1, &action)) ||
			FAILED(action->get_Type(&actionType)) ||
			actionType != TASK_ACTION_EXEC)
		{
			return xucrun::autostart::Status::Disabled;
		}
		ComPtr<IExecAction> execAction;
		BSTR actionPath = nullptr;
		BSTR arguments = nullptr;
		if (FAILED(action.As(&execAction)) ||
			FAILED(execAction->get_Path(&actionPath)) ||
			!EqualsAndFree(actionPath, executablePath) ||
			FAILED(execAction->get_Arguments(&arguments)))
		{
			return xucrun::autostart::Status::Disabled;
		}
		const bool noArguments = !arguments || arguments[0] == L'\0';
		SysFreeString(arguments);
		if (!noArguments)
			return xucrun::autostart::Status::Disabled;

		ComPtr<ITaskSettings> settings;
		BSTR executionLimit = nullptr;
		TASK_INSTANCES_POLICY instances = TASK_INSTANCES_PARALLEL;
		if (FAILED(definition->get_Settings(&settings)) ||
			FAILED(settings->get_ExecutionTimeLimit(&executionLimit)) ||
			!EqualsAndFree(executionLimit, L"PT0S") ||
			FAILED(settings->get_MultipleInstances(&instances)) ||
			instances != TASK_INSTANCES_IGNORE_NEW)
		{
			return xucrun::autostart::Status::Disabled;
		}
		return xucrun::autostart::Status::Enabled;
	}

	xucrun::autostart::Status QueryStandaloneStatus()
	{
		std::wstring sid;
		std::wstring executablePath;
		if (!xucrun::account_identity::GetCurrentUserSID(sid) ||
			!GetModulePath(executablePath))
		{
			return xucrun::autostart::Status::Unavailable;
		}

		const HRESULT initializeResult =
			CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
		const bool uninitialize =
			initializeResult == S_OK || initializeResult == S_FALSE;
		if (FAILED(initializeResult) && initializeResult != RPC_E_CHANGED_MODE)
			return xucrun::autostart::Status::Unavailable;

		ComPtr<ITaskService> service;
		HRESULT result = CoCreateInstance(
			__uuidof(TaskScheduler), nullptr, CLSCTX_INPROC_SERVER,
			__uuidof(ITaskService), &service);
		if (SUCCEEDED(result))
		{
			VARIANT empty;
			VariantInit(&empty);
			result = service->Connect(empty, empty, empty, empty);
		}
		xucrun::autostart::Status status = xucrun::autostart::Status::Unavailable;
		if (SUCCEEDED(result))
		{
			status = ValidateScheduledTask(service.Get(), sid, executablePath);
		}
		else if (IsMissingTask(result))
		{
			status = xucrun::autostart::Status::Disabled;
		}
		// Release apartment-bound interfaces before uninitializing COM.
		service.Reset();
		if (uninitialize)
			CoUninitialize();
		return status;
	}

	std::wstring Quote(const std::wstring& value)
	{
		return L"\"" + value + L"\"";
	}

	bool GetPowerShellPath(std::wstring& path)
	{
		std::vector<wchar_t> windowsDirectory(MAX_PATH);
		const UINT length = GetWindowsDirectoryW(
			windowsDirectory.data(), static_cast<UINT>(windowsDirectory.size()));
		if (length == 0 || length >= windowsDirectory.size())
			return false;
		path.assign(windowsDirectory.data(), length);
		path += L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
		return IsRegularFile(path);
	}

	void ShowChangeFailure(HWND owner, DWORD error)
	{
		xucrun::ui::ShowMessageBox(owner,
			xucrun::localization::Format(
				xucrun::localization::TrayTextId::AutostartChangeFailed,
				{ xucrun::windows_error::FormatWindowsError(error) }),
			xucrun::ui::GetWindowTitle(xucrun::localization::GetText(
				xucrun::localization::TextId::ErrorTitle)),
			MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
	}
}

namespace xucrun::autostart
{
	bool GetMaintenanceScriptPath(std::wstring& path)
	{
		return GetInstalledMaintenanceScript(path);
	}

	Status QueryStatus()
	{
		std::wstring maintenanceScriptPath;
		if (!GetInstalledMaintenanceScript(maintenanceScriptPath))
			return Status::Unavailable;
		return QueryStandaloneStatus();
	}

	bool SetEnabled(HWND owner, bool enabled)
	{
		std::wstring scriptPath;
		if (!GetInstalledMaintenanceScript(scriptPath))
		{
			ShowChangeFailure(owner, ERROR_FILE_NOT_FOUND);
			return false;
		}

		std::wstring powershellPath;
		if (!GetPowerShellPath(powershellPath))
		{
			ShowChangeFailure(owner, ERROR_FILE_NOT_FOUND);
			return false;
		}
		std::wstring parameters =
			L"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " +
			Quote(scriptPath) + (enabled
				? L" -EnableAutostart"
				: L" -DisableAutostart");
		std::wstring sid;
		if (!account_identity::GetCurrentUserSID(sid))
		{
			ShowChangeFailure(owner, ERROR_NO_SUCH_USER);
			return false;
		}
		parameters += L" -UserSid " + Quote(sid);

		SHELLEXECUTEINFOW executeInfo = { sizeof(executeInfo) };
		executeInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
		executeInfo.hwnd = owner;
		executeInfo.lpVerb = L"runas";
		executeInfo.lpFile = powershellPath.c_str();
		executeInfo.lpParameters = parameters.c_str();
		executeInfo.nShow = SW_HIDE;
		if (!ShellExecuteExW(&executeInfo))
		{
			ShowChangeFailure(owner, GetLastError());
			return false;
		}
		const DWORD waitResult = WaitForSingleObject(executeInfo.hProcess, INFINITE);
		DWORD exitCode = ERROR_GEN_FAILURE;
		const bool completed = waitResult == WAIT_OBJECT_0 &&
			GetExitCodeProcess(executeInfo.hProcess, &exitCode);
		CloseHandle(executeInfo.hProcess);
		if (!completed || exitCode != ERROR_SUCCESS)
		{
			ShowChangeFailure(owner,
				completed ? exitCode : GetLastError());
			return false;
		}

		ui::ShowMessageBox(owner,
			localization::GetText(enabled
				? localization::TrayTextId::AutostartEnabled
				: localization::TrayTextId::AutostartDisabled),
			broker::ProductName,
			MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND | MB_TOPMOST);
		return true;
	}

	int ShowStatus(HWND owner)
	{
		const Status status = QueryStatus();
		const localization::TrayTextId text = status == Status::Enabled
			? localization::TrayTextId::AutostartStatusEnabled
			: status == Status::Disabled
				? localization::TrayTextId::AutostartStatusDisabled
				: localization::TrayTextId::AutostartStatusUnavailable;
		ui::ShowMessageBox(owner, localization::GetText(text),
			broker::ProductName,
			MB_OK | (status == Status::Unavailable
				? MB_ICONERROR : MB_ICONINFORMATION));
		return status == Status::Enabled ? 0 :
			status == Status::Disabled ? 1 : 2;
	}
}
