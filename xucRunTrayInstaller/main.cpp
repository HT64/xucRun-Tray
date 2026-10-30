// Purpose: Extracts the protected Tray add-on payload and starts its graphical installer.
// Approach: Writes embedded resources to a secured temporary directory, launches PowerShell, and cleans up.
#include <Windows.h>
#include <ShlObj.h>
#include <sddl.h>

#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>
#include <vector>

#include "resource.h"

namespace
{
    struct PayloadFile
    {
        int resourceId;
        const wchar_t* relativePath;
        bool addUtf8Bom;
    };

    std::wstring GetLastErrorMessage(DWORD error)
    {
        wchar_t* message = nullptr;
        const DWORD length = FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS,
            nullptr, error, 0, reinterpret_cast<wchar_t*>(&message), 0, nullptr);
        std::wstring result = length && message ? message : L"Unknown error";
        if (message)
            LocalFree(message);
        return result;
    }

    std::filesystem::path CreateTemporaryDirectory()
    {
        wchar_t* programData = nullptr;
        const HRESULT folderResult = SHGetKnownFolderPath(
            FOLDERID_ProgramData, KF_FLAG_DEFAULT, nullptr, &programData);
        if (FAILED(folderResult))
            throw std::system_error(folderResult, std::system_category());
        const std::filesystem::path programDataPath(programData);
        CoTaskMemFree(programData);

        GUID identifier = {};
        if (FAILED(CoCreateGuid(&identifier)))
            throw std::runtime_error("A secure temporary directory name could not be created.");
        wchar_t identifierText[40] = {};
        if (StringFromGUID2(identifier, identifierText, ARRAYSIZE(identifierText)) == 0)
            throw std::runtime_error("A secure temporary directory name could not be formatted.");

        PSECURITY_DESCRIPTOR descriptor = nullptr;
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            L"D:P(A;;FA;;;SY)(A;;FA;;;BA)", SDDL_REVISION_1, &descriptor, nullptr))
        {
            throw std::system_error(GetLastError(), std::system_category());
        }
        SECURITY_ATTRIBUTES security = {};
        security.nLength = sizeof(security);
        security.lpSecurityDescriptor = descriptor;
        const std::filesystem::path directory =
            programDataPath / (L"xucRun-Tray-Installer-" + std::wstring(identifierText));
        const BOOL created = CreateDirectoryW(directory.c_str(), &security);
        const DWORD createError = created ? ERROR_SUCCESS : GetLastError();
        LocalFree(descriptor);
        if (!created)
            throw std::system_error(createError, std::system_category());
        return directory;
    }

    void ExtractResource(const std::filesystem::path& root, const PayloadFile& payload)
    {
        HRSRC resource = FindResourceW(
            nullptr, MAKEINTRESOURCEW(payload.resourceId), RT_RCDATA);
        if (!resource)
            throw std::system_error(GetLastError(), std::system_category());
        HGLOBAL loaded = LoadResource(nullptr, resource);
        const DWORD size = SizeofResource(nullptr, resource);
        const auto* data = static_cast<const unsigned char*>(LockResource(loaded));
        if (!loaded || !data || size == 0)
            throw std::runtime_error("An embedded Tray installer resource is unavailable.");

        const std::filesystem::path destination = root / payload.relativePath;
        std::filesystem::create_directories(destination.parent_path());
        std::ofstream output(destination, std::ios::binary | std::ios::trunc);
        if (!output)
            throw std::runtime_error("An extracted Tray installer file could not be created.");
        if (payload.addUtf8Bom &&
            !(size >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf))
        {
            constexpr unsigned char bom[] = { 0xef, 0xbb, 0xbf };
            output.write(reinterpret_cast<const char*>(bom), sizeof(bom));
        }
        output.write(reinterpret_cast<const char*>(data), size);
        if (!output)
            throw std::runtime_error("An embedded Tray installer file could not be extracted.");
    }

    std::wstring Quote(const std::wstring& value)
    {
        return L"\"" + value + L"\"";
    }

    DWORD RunInstaller(
        const std::filesystem::path& packageDirectory,
        const std::filesystem::path& installerPath,
        const std::filesystem::path& diagnosticLogPath)
    {
        wchar_t windowsDirectory[MAX_PATH] = {};
        const UINT length = GetWindowsDirectoryW(windowsDirectory, ARRAYSIZE(windowsDirectory));
        if (length == 0 || length >= ARRAYSIZE(windowsDirectory))
            throw std::system_error(GetLastError(), std::system_category());
        const std::filesystem::path powershell = std::filesystem::path(windowsDirectory) /
            L"System32\\WindowsPowerShell\\v1.0\\powershell.exe";
        const std::filesystem::path script = packageDirectory / L"Installer-Gui.ps1";
        std::wstring commandLine = Quote(powershell.wstring()) +
            L" -NoProfile -ExecutionPolicy Bypass -File " + Quote(script.wstring()) +
            L" -PackageDirectory " + Quote(packageDirectory.wstring()) +
            L" -InstallerPath " + Quote(installerPath.wstring()) +
            L" -DiagnosticLogPath " + Quote(diagnosticLogPath.wstring());

        STARTUPINFOW startup = {};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process = {};
        std::vector<wchar_t> writable(commandLine.begin(), commandLine.end());
        writable.push_back(L'\0');
        if (!CreateProcessW(
            powershell.c_str(), writable.data(), nullptr, nullptr, FALSE,
            CREATE_NO_WINDOW, nullptr, packageDirectory.c_str(), &startup, &process))
        {
            throw std::system_error(GetLastError(), std::system_category());
        }
        CloseHandle(process.hThread);
        WaitForSingleObject(process.hProcess, INFINITE);
        DWORD exitCode = ERROR_INSTALL_FAILURE;
        if (!GetExitCodeProcess(process.hProcess, &exitCode))
        {
            const DWORD error = GetLastError();
            CloseHandle(process.hProcess);
            throw std::system_error(error, std::system_category());
        }
        CloseHandle(process.hProcess);
        return exitCode;
    }

    std::filesystem::path GetDiagnosticLogPath()
    {
        const DWORD requiredLength = GetTempPathW(0, nullptr);
        if (requiredLength == 0)
            throw std::system_error(GetLastError(), std::system_category());
        std::vector<wchar_t> buffer(requiredLength);
        const DWORD length = GetTempPathW(
            static_cast<DWORD>(buffer.size()), buffer.data());
        if (length == 0 || length >= buffer.size())
            throw std::system_error(GetLastError(), std::system_category());
        return std::filesystem::path(buffer.data()) /
            L"xucRun-Tray-Installer.log";
    }

    std::wstring RemoveTemporaryDirectory(const std::filesystem::path& directory)
    {
        std::error_code error;
        std::filesystem::remove_all(directory, error);
        return error ? GetLastErrorMessage(static_cast<DWORD>(error.value())) : L"";
    }
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    std::filesystem::path temporaryDirectory;
    try
    {
        wchar_t installerPath[32768] = {};
        const DWORD length = GetModuleFileNameW(
            nullptr, installerPath, ARRAYSIZE(installerPath));
        if (length == 0 || length >= ARRAYSIZE(installerPath))
            throw std::system_error(GetLastError(), std::system_category());

        temporaryDirectory = CreateTemporaryDirectory();
        const PayloadFile files[] = {
            { IDR_GUI_SCRIPT, L"Installer-Gui.ps1", true },
            { IDR_MACHINE_INSTALLER, L"Install-xucRunTray.ps1", false },
            { IDR_SIGN_PACKAGE, L"Sign-xucRunTrayPackage.ps1", false },
            { IDR_MANIFEST, L"TrayPackage.json", false },
            { IDR_TRAY, L"xucRunTray.exe", false },
            { IDR_TRAY_LANGUAGE_DE, L"Languages\\xucRunTray.de-DE.dll", false },
            { IDR_TRAY_LANGUAGE_EN, L"Languages\\xucRunTray.en-US.dll", false }
        };
        for (const PayloadFile& file : files)
            ExtractResource(temporaryDirectory, file);

        const std::filesystem::path diagnosticLogPath = GetDiagnosticLogPath();
        std::error_code logCleanupError;
        std::filesystem::remove(diagnosticLogPath, logCleanupError);
        const DWORD exitCode = RunInstaller(
            temporaryDirectory, installerPath, diagnosticLogPath);
        if (exitCode != ERROR_SUCCESS && exitCode != ERROR_INSTALL_USEREXIT)
        {
            const std::wstring message =
                L"xucRun Tray Installer ended unexpectedly.\n\nExit code: " +
                std::to_wstring(exitCode) + L"\nDiagnostic log:\n" +
                diagnosticLogPath.native();
            MessageBoxW(nullptr, message.c_str(), L"xucRun Tray Installer",
                MB_OK | MB_ICONERROR);
        }
        const std::wstring cleanupWarning = RemoveTemporaryDirectory(temporaryDirectory);
        if (!cleanupWarning.empty())
        {
            MessageBoxW(nullptr, cleanupWarning.c_str(), L"xucRun Tray Installer",
                MB_OK | MB_ICONWARNING);
        }
        return static_cast<int>(exitCode);
    }
    catch (const std::exception& exception)
    {
        std::wstring message = L"xucRun Tray Installer could not start.\n\n";
        for (const char* character = exception.what(); *character; ++character)
            message.push_back(static_cast<unsigned char>(*character));
        const std::wstring cleanupWarning = RemoveTemporaryDirectory(temporaryDirectory);
        if (!cleanupWarning.empty())
            message += L"\n\n" + cleanupWarning;
        MessageBoxW(nullptr, message.c_str(), L"xucRun Tray Installer",
            MB_OK | MB_ICONERROR);
        return ERROR_INSTALL_FAILURE;
    }
}
