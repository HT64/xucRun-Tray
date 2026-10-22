# Manual removal

**Language:** [Deutsch](../de/MANUAL_REMOVAL.md) | English

This document lists the artifacts created by xucRun Tray and describes their manual removal. Use
this procedure only if the normal Tray uninstaller cannot be used or does not complete
successfully. The normal uninstaller is the preferred and safer method.

The Tray is an optional component of xucRun. Removing it must not remove the xucRun Core, broker
service, Core configuration, signing certificate, stored credentials, approvals, backups, or
broker data.

## Scope

The procedure removes Tray-owned installed files, processes, scheduled tasks, and its uninstall
entry. It does not erase general Windows history such as Task Scheduler events, Application
events, Prefetch, Amcache, compatibility or recent-item data, restore points, external backups, or
records maintained by security and management software.

## Artifact inventory

| Type | Path or name | Notes |
|---|---|---|
| Tray executable | `%ProgramFiles%\xucRun\xucRunTray.exe` | The directory is shared with the Core |
| Installer script | `%ProgramFiles%\xucRun\Install-xucRunTray.ps1` | Tray-specific |
| Language files | `%ProgramFiles%\xucRun\Languages\xucRunTray.de-DE.dll` and `xucRunTray.en-US.dll` | Tray-specific |
| Processes | `xucRunTray.exe` | One or more user sessions can have a running instance |
| Scheduled-task folder | `\xucRun\` | Shared folder; remove it only when empty |
| Scheduled tasks | `BrokerStatus-<user SID>` | One task can exist for each configured Windows user |
| Uninstall entry | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray` | Machine-wide |
| Failed-install staging | `%ProgramFiles%\xucRun\.xucRun-Tray-staging-<32 hexadecimal characters>` | Normally removed automatically |
| Failed-install backup | `%ProgramFiles%\xucRun\.xucRun-Tray-backup-<32 hexadecimal characters>` | Normally removed automatically |
| Installer extraction | `%ProgramData%\xucRun-Tray-Installer-<32 hexadecimal characters>` | Normally removed automatically |
| Installer diagnostic | `%TEMP%\xucRun-Tray-Installer.log` | Used when the graphical installer cannot complete; normally removed before a new run |

The Tray does not create a certificate, broker service, credentials, approvals, or a separate
product-data directory. Its uninstall diagnostics are written to the Core-owned
`%ProgramData%\xucRun\InstallerLogs` directory; do not remove that directory while the Core remains
installed.

## Manual removal procedure

Run the commands below in an elevated Windows PowerShell 5.1 window.

### 1. Stop all installed Tray instances

The following command limits termination to processes running the installed Tray binary. It does
not stop unrelated processes with a similar name:

```powershell
$trayPath = Join-Path $env:ProgramFiles 'xucRun\xucRunTray.exe'

Get-CimInstance Win32_Process -Filter "Name = 'xucRunTray.exe'" |
    Where-Object {
        $_.ExecutablePath -and
        $_.ExecutablePath.Equals(
            $trayPath,
            [StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

Run this while all user sessions that may contain the Tray are still accessible. The query covers
processes in all sessions visible to the elevated administrator.

### 2. Remove all Tray scheduled tasks

```powershell
Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName.StartsWith('BrokerStatus-') } |
    Unregister-ScheduledTask -Confirm:$false
```

Each task name contains the SID of the Windows user for whom it starts the Tray. Remove all
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
$installDirectory = Join-Path $env:ProgramFiles 'xucRun'
$trayFiles = @(
    (Join-Path $installDirectory 'xucRunTray.exe'),
    (Join-Path $installDirectory 'Install-xucRunTray.ps1'),
    (Join-Path $installDirectory 'Languages\xucRunTray.de-DE.dll'),
    (Join-Path $installDirectory 'Languages\xucRunTray.en-US.dll')
)

foreach ($path in $trayFiles) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
```

Do not delete `%ProgramFiles%\xucRun` or its `Languages` subdirectory while they contain Core files.
The Tray shares these directories with xucRun.

### 4. Remove the Tray uninstall entry

```powershell
Remove-Item -LiteralPath `
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray' `
    -Recurse -Force -ErrorAction SilentlyContinue
```

Do not remove the separate `...\Uninstall\xucRun` entry, which belongs to the Core.

### 5. Inspect interrupted-installation remnants

Inspect the paths in the artifact inventory for staging, backup, extraction, or diagnostic
remnants. They are normally removed automatically and should exist only after interruption or
failure.

Before deleting an individual staging or backup directory:

1. verify its complete name, including the 32 hexadecimal characters;
2. verify that it contains only Tray files from the interrupted operation;
3. ensure that no installer is still running.

Do not recursively delete `%ProgramFiles%\xucRun`, `%ProgramData%`, or `%TEMP%`, and do not use a
broad wildcard deletion. A backup directory can contain the previous working Tray files; retain
it until the installed Tray files have been checked or restored.

The fixed `%TEMP%\xucRun-Tray-Installer.log` belongs to the Windows account that started the
graphical installer. Other accounts can therefore have their own file at the corresponding
expanded path.

## Verification

```powershell
$installDirectory = Join-Path $env:ProgramFiles 'xucRun'

Get-CimInstance Win32_Process -Filter "Name = 'xucRunTray.exe'" |
    Select-Object ProcessId, ExecutablePath

Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName.StartsWith('BrokerStatus-') }

@(
    'xucRunTray.exe',
    'Install-xucRunTray.ps1',
    'Languages\xucRunTray.de-DE.dll',
    'Languages\xucRunTray.en-US.dll'
) | ForEach-Object {
    Test-Path -LiteralPath (Join-Path $installDirectory $_)
}

Test-Path -LiteralPath `
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray'
```

Successful verification produces no Tray process or `BrokerStatus-` task, and all five
`Test-Path` results are `False`. If the Core remains installed, its files, service, data,
certificate, credentials, and uninstall entry must still be present and unchanged.

If the Core must also be removed, follow its separate
[manual removal instructions](https://github.com/HT64/xucRun/blob/main/docs/en/MANUAL_REMOVAL.md)
only after completing the Tray removal.
