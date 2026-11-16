<!--
Purpose: Describes manual xucRun Tray removal when normal uninstallation is unavailable.
Approach: Identifies Tray artifacts, removes them step by step, and explicitly protects xucRun data.
-->
# Manual removal

**Language:** [Deutsch](../de/MANUAL_REMOVAL.md) | English

Use this procedure only if [normal Tray uninstallation](INSTALLATION.md#uninstall) is unavailable
or cannot complete.

xucRun Tray is an optional component of xucRun. Removing it must not remove the xucRun Core, broker
service, Core configuration, signing certificate, stored credentials, approvals, backups, or
broker data.

Existing Windows events and external copies are not removed.

## Artifact inventory

| Type | Path or name | Notes |
|---|---|---|
| Tray files | `%ProgramFiles%\xucRun\xucRunTray.exe`, `Install-xucRunTray.ps1`, and `Languages\xucRunTray.*.dll` | Directories are shared with the Core |
| Legal files | `%ProgramFiles%\xucRun\Licenses\LICENSE-xucRun-Tray.txt` and `NOTICE-xucRun-Tray.txt` | The `Licenses` directory is shared with the Core; older installations may have left files with the same names directly under `%ProgramFiles%\xucRun` |
| Processes | `xucRunTray.exe` | One or more user sessions can have a running instance |
| Scheduled-task folder | `\xucRun\` | Shared folder; remove it only when empty |
| Scheduled tasks | `BrokerStatus-<user SID>` | One task can exist for each configured Windows user |
| Uninstall entry | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray` | Machine-wide |

xucRun Tray does not create a certificate, broker service, credentials, approvals, or a separate
product-data directory. Its uninstall diagnostics are written to the Core-owned
`%ProgramData%\xucRun\InstallerLogs` directory; do not remove that directory while the Core remains
installed.

## Manual removal procedure

Start 64-bit Windows PowerShell 5.1 as an administrator and complete the following steps in the
given order. First resolve the trusted Windows Program Files directory in that window through the
Windows API rather than an inherited environment variable:

```powershell
if (-not [Environment]::Is64BitProcess) {
    throw 'Manual removal requires 64-bit PowerShell.'
}
$programFilesDirectory = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
if ([string]::IsNullOrWhiteSpace($programFilesDirectory)) {
    throw 'The Windows Program Files directory could not be resolved.'
}
```

### 1. Stop all installed Tray instances

The following command limits termination to processes running the installed Tray binary. It does
not stop unrelated processes with a similar name:

```powershell
$trayPath = Join-Path $programFilesDirectory 'xucRun\xucRunTray.exe'

Get-CimInstance Win32_Process -Filter "Name = 'xucRunTray.exe'" |
    Where-Object {
        $_.ExecutablePath -and
        $_.ExecutablePath.Equals(
            $trayPath,
            [StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    }
```

Run this while all user sessions that may contain xucRun Tray are still accessible. The query covers
processes in all sessions visible to the elevated administrator.

### 2. Remove all Tray scheduled tasks

```powershell
Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName.StartsWith('BrokerStatus-') } |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
```

Each task name contains the SID of the Windows user for whom it starts xucRun Tray. Remove all
`BrokerStatus-<SID>` tasks, not only the task for the currently signed-in user.

Remove the `\xucRun\` folder only if it contains no remaining tasks or subfolders:

```powershell
$scheduler = New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$root = $scheduler.GetFolder('\')
try {
    $folder = $root.GetFolder('xucRun')
    if ($folder.GetTasks(0).Count -eq 0 -and
        $folder.GetFolders(0).Count -eq 0) {
        $root.DeleteFolder('xucRun', 0)
    }
}
catch {
    if ($_.Exception.HResult -notin @(-2147024894, -2147024893)) {
        throw
    }
}
```

Do not delete the folder if another task or subfolder uses it.

### 3. Remove Tray files

```powershell
$installDirectory = Join-Path $programFilesDirectory 'xucRun'
$trayFiles = @(
    (Join-Path $installDirectory 'xucRunTray.exe'),
    (Join-Path $installDirectory 'Install-xucRunTray.ps1'),
    (Join-Path $installDirectory 'Languages\xucRunTray.de-DE.dll'),
    (Join-Path $installDirectory 'Languages\xucRunTray.en-US.dll'),
    (Join-Path $installDirectory 'Licenses\LICENSE-xucRun-Tray.txt'),
    (Join-Path $installDirectory 'Licenses\NOTICE-xucRun-Tray.txt'),
    (Join-Path $installDirectory 'LICENSE-xucRun-Tray.txt'),
    (Join-Path $installDirectory 'NOTICE-xucRun-Tray.txt')
)

foreach ($path in $trayFiles) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $path) {
            throw "The Tray file could not be removed: $path"
        }
    }
}
```

Do not delete `%ProgramFiles%\xucRun` or its `Languages` and `Licenses` subdirectories while they
contain Core files. xucRun Tray shares these directories with xucRun.

### 4. Remove xucRun Tray uninstall entry

```powershell
$trayUninstallPath =
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray'
if (Test-Path -LiteralPath $trayUninstallPath) {
    Remove-Item -LiteralPath $trayUninstallPath -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $trayUninstallPath) {
        throw 'The Tray uninstall entry could not be removed completely.'
    }
}
```

Do not remove the separate `...\Uninstall\xucRun` entry, which belongs to the Core.

### 5. Inspect interrupted-installation remnants

After an interruption or failure, inspect the following remnants that are normally removed
automatically:

- `%ProgramFiles%\xucRun\.xucRun-Tray-staging-<32 hexadecimal characters>`;
- `%ProgramFiles%\xucRun\.xucRun-Tray-backup-<32 hexadecimal characters>`;
- `%ProgramData%\xucRun-Tray-Installer-<32 hexadecimal characters>`;
- `%TEMP%\xucRun-Tray-Installer.log` for the account that started the graphical installer.

Before deleting an individual staging or backup directory:

1. verify its complete name, including the 32 hexadecimal characters;
2. verify that it contains only Tray files from the interrupted operation;
3. ensure that no installer is still running.

Do not recursively delete `%ProgramFiles%\xucRun`, `%ProgramData%`, or `%TEMP%`, and do not use a
broad wildcard deletion. A backup directory can contain the previous working Tray files; retain
it until the installed Tray files have been checked or restored.

## Verification

```powershell
$installDirectory = Join-Path $programFilesDirectory 'xucRun'

$trayProcessPresent = @(
    Get-CimInstance Win32_Process -Filter "Name = 'xucRunTray.exe'" |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath.Equals(
                (Join-Path $installDirectory 'xucRunTray.exe'),
                [StringComparison]::OrdinalIgnoreCase)
        }
).Count -ne 0

$trayTasksPresent = @(
    Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName.StartsWith('BrokerStatus-') }
).Count -ne 0

$trayLanguageFilesPresent = @(
    @(
        'Languages\xucRunTray.de-DE.dll',
        'Languages\xucRunTray.en-US.dll'
    ) | Where-Object {
        Test-Path -LiteralPath (Join-Path $installDirectory $_)
    }
).Count -ne 0

$trayLegalFilesPresent = @(
    @(
        'Licenses\LICENSE-xucRun-Tray.txt',
        'Licenses\NOTICE-xucRun-Tray.txt',
        'LICENSE-xucRun-Tray.txt',
        'NOTICE-xucRun-Tray.txt'
    ) |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $installDirectory $_)
        }
).Count -ne 0

[pscustomobject]@{
    TrayProcessPresent = $trayProcessPresent
    TrayTasksPresent = $trayTasksPresent
    TrayExecutablePresent = Test-Path -LiteralPath (
        Join-Path $installDirectory 'xucRunTray.exe')
    TrayInstallerScriptPresent = Test-Path -LiteralPath (
        Join-Path $installDirectory 'Install-xucRunTray.ps1')
    TrayLanguageFilesPresent = $trayLanguageFilesPresent
    TrayLegalFilesPresent = $trayLegalFilesPresent
    UninstallEntryPresent = Test-Path -LiteralPath $trayUninstallPath
}
```

After successful removal, every property with the suffix `Present` is `False`. If the Core remains
installed, its files, service, data, certificate, credentials, and uninstall entry must still be
present and unchanged.

If the Core must also be removed, follow its separate
[manual removal instructions](https://github.com/HT64/xucRun/blob/main/docs/en/MANUAL_REMOVAL.md)
only after completing xucRun Tray removal.
