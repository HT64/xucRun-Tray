// Purpose: Executes tray actions selected from the broker status menu.
#include "ClientStatusActions.h"
#include "ClientStatusActionRouting.h"

#include <shellapi.h>

#include <vector>

#include "BrokerPipeClient.h"
#include "ClientLogging.h"
#include "ClientUiCommon.h"
#include "ClientWindowActivation.h"
#include "ClientWindowsError.h"
#include "TrayLocalization.h"

namespace xucrun::status_actions
{
	namespace
	{
		bool GetCoreClientPath(std::wstring& path)
		{
			std::vector<wchar_t> executablePath(512);
			for (;;)
			{
				const DWORD length = GetModuleFileNameW(nullptr,
					executablePath.data(), static_cast<DWORD>(executablePath.size()));
				if (length == 0)
					return false;
				if (length < executablePath.size() - 1)
				{
					path.assign(executablePath.data(), length);
					break;
				}
				executablePath.resize(executablePath.size() * 2);
			}
			const std::size_t separator = path.find_last_of(L"\\/");
			if (separator == std::wstring::npos)
				return false;
			path.replace(separator + 1, std::wstring::npos, L"xucRun.exe");
			return true;
		}

		bool LaunchClientCommandAndWait(
			HWND owner, const wchar_t* argument, bool elevated)
		{
			std::wstring executablePath;
			if (!GetCoreClientPath(executablePath))
			{
				ui::ShowMessageBox(owner,
					localization::Format(
						localization::TextId::CommandLaunchFailed, { argument }),
					broker::ProductName, MB_OK | MB_ICONERROR);
				return false;
			}
			SHELLEXECUTEINFOW executeInfo = { sizeof(executeInfo) };
			executeInfo.fMask = SEE_MASK_NOCLOSEPROCESS;
			executeInfo.hwnd = owner;
			executeInfo.lpVerb = elevated ? L"runas" : L"open";
			executeInfo.lpFile = executablePath.c_str();
			executeInfo.lpParameters = argument;
			executeInfo.nShow = SW_HIDE;
			if (!ShellExecuteExW(&executeInfo))
			{
				ui::ShowMessageBox(owner,
					localization::Format(
						localization::TextId::CommandLaunchFailed, { argument }),
					broker::ProductName, MB_OK | MB_ICONERROR);
				return false;
			}

			const DWORD waitResult = WaitForSingleObject(executeInfo.hProcess, INFINITE);
			DWORD exitCode = ERROR_GEN_FAILURE;
			const bool exitCodeAvailable = waitResult == WAIT_OBJECT_0 &&
				GetExitCodeProcess(executeInfo.hProcess, &exitCode);
			CloseHandle(executeInfo.hProcess);
			if (!exitCodeAvailable)
			{
				ui::ShowMessageBox(owner,
					localization::Format(
						localization::TextId::CommandLaunchFailed, { argument }),
					broker::ProductName, MB_OK | MB_ICONERROR);
				return false;
			}
			return exitCode == ERROR_SUCCESS;
		}

		bool ShowLogFile(HWND owner)
		{
			std::wstring path;
			if (!client_logging::TryGetExistingLogFilePath(path))
			{
				ui::ShowMessageBox(owner, localization::GetText(
					localization::TrayTextId::LogFileUnavailable),
					ui::GetWindowTitle(localization::GetText(
						localization::TextId::WarningTitle)),
					MB_OK | MB_ICONWARNING | MB_SETFOREGROUND | MB_TOPMOST);
				return false;
			}

			SHELLEXECUTEINFOW executeInfo = { sizeof(executeInfo) };
			executeInfo.fMask = SEE_MASK_FLAG_NO_UI;
			executeInfo.hwnd = owner;
			executeInfo.lpVerb = L"open";
			executeInfo.lpFile = path.c_str();
			executeInfo.nShow = SW_SHOWNORMAL;
			if (ShellExecuteExW(&executeInfo))
				return true;

			DWORD error = GetLastError();
			if (error == ERROR_NO_ASSOCIATION)
			{
				wchar_t systemDirectory[MAX_PATH] = {};
				const UINT systemDirectoryLength = GetSystemDirectoryW(
					systemDirectory, ARRAYSIZE(systemDirectory));
				if (systemDirectoryLength == 0)
				{
					error = GetLastError();
				}
				else if (systemDirectoryLength >= ARRAYSIZE(systemDirectory))
				{
					error = ERROR_INSUFFICIENT_BUFFER;
				}
				else
				{
					std::wstring editorPath(systemDirectory, systemDirectoryLength);
					editorPath += L"\\notepad.exe";
					const std::wstring parameters = L"\"" + path + L"\"";
					SHELLEXECUTEINFOW editorInfo = { sizeof(editorInfo) };
					editorInfo.fMask = SEE_MASK_FLAG_NO_UI;
					editorInfo.hwnd = owner;
					editorInfo.lpVerb = L"open";
					editorInfo.lpFile = editorPath.c_str();
					editorInfo.lpParameters = parameters.c_str();
					editorInfo.nShow = SW_SHOWNORMAL;
					if (ShellExecuteExW(&editorInfo))
						return true;
					error = GetLastError();
				}
			}

			ui::ShowMessageBox(owner, localization::Format(
					localization::TrayTextId::LogFileOpenFailed,
					{ path, windows_error::FormatWindowsError(error) }),
				ui::GetWindowTitle(localization::GetText(
					localization::TextId::ErrorTitle)),
				MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
			return false;
		}

		bool DeleteLogFile(HWND owner)
		{
			std::wstring path;
			if (!client_logging::TryGetExistingLogFilePath(path))
			{
				ui::ShowMessageBox(owner, localization::GetText(
					localization::TrayTextId::LogFileUnavailable),
					ui::GetWindowTitle(localization::GetText(
						localization::TextId::WarningTitle)),
					MB_OK | MB_ICONWARNING | MB_SETFOREGROUND | MB_TOPMOST);
				return false;
			}
			if (ui::ShowMessageBox(owner,
				localization::Format(
					localization::TrayTextId::LogFileDeleteConfirmation, { path }),
				ui::GetWindowTitle(localization::GetText(
					localization::TextId::WarningTitle)),
				MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 |
					MB_SETFOREGROUND | MB_TOPMOST) != IDYES)
			{
				return false;
			}
			if (!DeleteFileW(path.c_str()))
			{
				const DWORD error = GetLastError();
				ui::ShowMessageBox(owner, localization::Format(
						localization::TrayTextId::LogFileDeleteFailed,
						{ path, windows_error::FormatWindowsError(error) }),
					ui::GetWindowTitle(localization::GetText(
						localization::TextId::ErrorTitle)),
					MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
				return false;
			}
			ui::ShowMessageBox(owner, localization::GetText(
					localization::TrayTextId::LogFileDeleteSucceeded),
				ui::GetWindowTitle(),
				MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND | MB_TOPMOST);
			return true;
		}

		bool DeleteAllLogFiles(HWND owner)
		{
			std::wstring directory;
			std::vector<std::wstring> paths;
			DWORD error = ERROR_SUCCESS;
			if (!client_logging::GetExistingLogFiles(directory, paths, error))
			{
				ui::ShowMessageBox(owner, localization::Format(
						localization::TrayTextId::LogFilesQueryFailed,
						{ directory, windows_error::FormatWindowsError(error) }),
					ui::GetWindowTitle(localization::GetText(
						localization::TextId::ErrorTitle)),
					MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
				return false;
			}
			if (paths.empty())
			{
				ui::ShowMessageBox(owner, localization::GetText(
					localization::TrayTextId::LogFileUnavailable),
					ui::GetWindowTitle(localization::GetText(
						localization::TextId::WarningTitle)),
					MB_OK | MB_ICONWARNING | MB_SETFOREGROUND | MB_TOPMOST);
				return false;
			}
			if (ui::ShowMessageBox(owner,
				localization::Format(
					localization::TrayTextId::LogFilesDeleteAllConfirmation,
					{ std::to_wstring(paths.size()), directory }),
				ui::GetWindowTitle(localization::GetText(
					localization::TextId::WarningTitle)),
				MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 |
					MB_SETFOREGROUND | MB_TOPMOST) != IDYES)
			{
				return false;
			}

			size_t deletedCount = 0;
			size_t failedCount = 0;
			std::wstring firstFailedPath;
			DWORD firstError = ERROR_SUCCESS;
			for (const std::wstring& path : paths)
			{
				if (DeleteFileW(path.c_str()))
				++deletedCount;
				else
				{
					const DWORD deleteError = GetLastError();
					if (deleteError == ERROR_FILE_NOT_FOUND)
						++deletedCount;
					else
					{
						++failedCount;
						if (firstFailedPath.empty())
						{
							firstFailedPath = path;
							firstError = deleteError;
						}
					}
				}
			}
			if (failedCount == 0)
			{
				ui::ShowMessageBox(owner, localization::Format(
						localization::TrayTextId::LogFilesDeleteAllSucceeded,
						{ std::to_wstring(deletedCount) }),
					ui::GetWindowTitle(),
					MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND | MB_TOPMOST);
				return true;
			}
			ui::ShowMessageBox(owner, localization::Format(
					localization::TrayTextId::LogFilesDeleteAllIncomplete,
					{ std::to_wstring(deletedCount), std::to_wstring(failedCount),
						firstFailedPath,
						windows_error::FormatWindowsError(firstError) }),
				ui::GetWindowTitle(localization::GetText(
					localization::TextId::ErrorTitle)),
				MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
			return false;
		}
	}

	bool LaunchClientCommand(HWND owner, const wchar_t* argument, bool elevated)
	{
		std::wstring executablePath;
		if (!GetCoreClientPath(executablePath) ||
			reinterpret_cast<INT_PTR>(ShellExecuteW(
				owner, elevated ? L"runas" : L"open", executablePath.c_str(),
				argument, nullptr, SW_SHOWNORMAL)) <= 32)
		{
			ui::ShowMessageBox(owner,
				localization::Format(
					localization::TextId::CommandLaunchFailed, { argument }),
				broker::ProductName, MB_OK | MB_ICONERROR);
			return false;
		}
		return true;
	}

	bool Execute(HWND owner, const Selection& selection)
	{
		const std::wstring_view coreArgument =
			GetCoreClientArgument(selection.action);
		if (!coreArgument.empty())
		{
			if (selection.action == Action::SetLanguageGerman ||
				selection.action == Action::SetLanguageEnglish)
			{
				return LaunchClientCommandAndWait(
					owner, coreArgument.data(), false);
			}
			return LaunchClientCommand(owner, coreArgument.data());
		}

		switch (selection.action)
		{
		case Action::ShowLogFile:
			return ShowLogFile(owner);
		case Action::DeleteLogFile:
			return DeleteLogFile(owner);
		case Action::DeleteAllLogFiles:
			return DeleteAllLogFiles(owner);
		case Action::ActivateProcessWindow:
			window_activation::ActivateTrackedProcessWindow(
				selection.process, selection.processWindow);
			return true;
		default:
			return false;
		}
	}
}
