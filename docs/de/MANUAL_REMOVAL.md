<!--
Purpose: Beschreibt die manuelle Entfernung von xucRun Tray, wenn die Deinstallation nicht nutzbar ist.
Approach: Identifiziert Tray-Artefakte, entfernt sie schrittweise und schützt ausdrücklich xucRun-Daten.
-->
# Manuelle Entfernung

**Sprache:** Deutsch | [English](../en/MANUAL_REMOVAL.md)

Verwenden Sie dieses Verfahren nur, wenn die
[normale Tray-Deinstallation](INSTALLATION.md#deinstallieren) nicht verfügbar ist oder nicht
abgeschlossen werden kann.

xucRun Tray ist eine optionale Komponente von xucRun. Seine Entfernung darf weder den xucRun Core
noch Brokerdienst, Core-Konfiguration, Signaturzertifikat, gespeicherte Anmeldeinformationen,
Freigaben, Sicherungen oder Brokerdaten entfernen.

Bereits geschriebene Windows-Ereignisse und externe Kopien werden nicht entfernt.

## Artefaktinventar

| Typ | Pfad oder Name | Hinweise |
|---|---|---|
| Tray-Dateien | `%ProgramFiles%\xucRun\xucRunTray.exe`, `Install-xucRunTray.ps1` und `Languages\xucRunTray.*.dll` | Verzeichnisse werden mit dem Core gemeinsam genutzt |
| Lizenzdateien | `%ProgramFiles%\xucRun\Licenses\LICENSE-xucRun-Tray.txt` und `NOTICE-xucRun-Tray.txt` | Das Verzeichnis `Licenses` wird mit dem Core gemeinsam genutzt; ältere Installationen können gleichnamige Dateien direkt unter `%ProgramFiles%\xucRun` hinterlassen haben |
| Prozesse | `xucRunTray.exe` | In mehreren Benutzersitzungen kann jeweils eine Instanz laufen |
| Aufgabenordner | `\xucRun\` | Gemeinsam genutzter Ordner; nur entfernen, wenn er leer ist |
| Geplante Aufgaben | `BrokerStatus-<Benutzer-SID>` | Für jeden eingerichteten Windows-Benutzer kann eine Aufgabe bestehen |
| Deinstallationseintrag | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray` | Rechnerweit |

xucRun Tray erzeugt weder ein Zertifikat noch einen Brokerdienst, Anmeldeinformationen, Freigaben
oder ein eigenes Produktdatenverzeichnis. Seine Deinstallationsdiagnose wird in das zum Core
gehörende Verzeichnis `%ProgramData%\xucRun\InstallerLogs` geschrieben. Entfernen Sie dieses
Verzeichnis nicht, solange der Core installiert bleibt.

## Verfahren zur manuellen Entfernung

Starten Sie eine 64-Bit-Windows-PowerShell 5.1 als Administrator und führen Sie darin die
folgenden Schritte vollständig in der angegebenen Reihenfolge aus. Ermitteln Sie in diesem Fenster
zuerst das vertrauenswürdige Windows-Programmverzeichnis über die Windows-API statt über eine
geerbte Umgebungsvariable:

```powershell
if (-not [Environment]::Is64BitProcess) {
    throw 'Die manuelle Entfernung erfordert eine 64-Bit-PowerShell.'
}
$programFilesDirectory = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
if ([string]::IsNullOrWhiteSpace($programFilesDirectory)) {
    throw 'Das Windows-Programmverzeichnis konnte nicht ermittelt werden.'
}
```

### 1. Alle installierten Tray-Instanzen beenden

Der folgende Befehl beschränkt das Beenden auf Prozesse, die das installierte Tray-Programm
ausführen. Fremde Prozesse mit einem ähnlichen Namen werden nicht beendet:

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

Führen Sie dies aus, solange alle Benutzersitzungen, in denen xucRun Tray laufen kann, noch
erreichbar sind. Die Abfrage erfasst die für den erhöhten Administrator sichtbaren Prozesse aller
Sitzungen.

### 2. Alle geplanten Tray-Aufgaben entfernen

```powershell
Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName.StartsWith('BrokerStatus-') } |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
```

Jeder Aufgabenname enthält die SID des Windows-Benutzers, für den xucRun Tray gestartet wird.
Entfernen Sie alle Aufgaben `BrokerStatus-<SID>`, nicht nur die Aufgabe des aktuell angemeldeten
Benutzers.

Entfernen Sie den Ordner `\xucRun\` nur, wenn er keine Aufgaben oder Unterordner mehr enthält:

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

Löschen Sie den Ordner nicht, wenn ihn eine andere Aufgabe oder ein Unterordner verwendet.

### 3. Tray-Dateien entfernen

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
            throw "Die Tray-Datei konnte nicht entfernt werden: $path"
        }
    }
}
```

Löschen Sie weder `%ProgramFiles%\xucRun` noch dessen Unterverzeichnisse `Languages` und
`Licenses`, solange sie Core-Dateien enthalten. xucRun Tray nutzt diese Verzeichnisse gemeinsam
mit xucRun.

### 4. Tray-Deinstallationseintrag entfernen

```powershell
$trayUninstallPath =
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray'
if (Test-Path -LiteralPath $trayUninstallPath) {
    Remove-Item -LiteralPath $trayUninstallPath -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $trayUninstallPath) {
        throw 'Der Tray-Deinstallationseintrag konnte nicht vollständig entfernt werden.'
    }
}
```

Entfernen Sie nicht den separaten Eintrag `...\Uninstall\xucRun`, der zum Core gehört.

### 5. Reste abgebrochener Installationen prüfen

Prüfen Sie nach einem Abbruch oder Fehler folgende normalerweise automatisch entfernte Reste:

- `%ProgramFiles%\xucRun\.xucRun-Tray-staging-<32 hexadezimale Zeichen>`;
- `%ProgramFiles%\xucRun\.xucRun-Tray-backup-<32 hexadezimale Zeichen>`;
- `%ProgramData%\xucRun-Tray-Installer-<32 hexadezimale Zeichen>`;
- `%TEMP%\xucRun-Tray-Installer.log` des Kontos, das den grafischen Installer gestartet hat.

Vor dem Löschen eines einzelnen Bereitstellungs- oder Sicherungsverzeichnisses:

1. Prüfen Sie den vollständigen Namen einschließlich der 32 hexadezimalen Zeichen.
2. Prüfen Sie, dass es ausschließlich Tray-Dateien des abgebrochenen Vorgangs enthält.
3. Stellen Sie sicher, dass kein Installer mehr läuft.

Löschen Sie weder `%ProgramFiles%\xucRun`, `%ProgramData%` noch `%TEMP%` rekursiv und verwenden Sie
keine weit gefasste Wildcard-Löschung. Ein Sicherungsverzeichnis kann die zuvor funktionsfähigen
Tray-Dateien enthalten; behalten Sie es, bis die installierten Tray-Dateien geprüft oder
wiederhergestellt wurden.

## Überprüfung

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

Bei erfolgreicher Entfernung sind alle Eigenschaften mit dem Suffix `Present` gleich `False`.
Bleibt der Core installiert, müssen seine Dateien, sein Dienst, seine Daten, sein Zertifikat, seine
Anmeldeinformationen und sein Deinstallationseintrag unverändert vorhanden sein.

Soll anschließend auch der Core entfernt werden, folge erst nach abgeschlossener Tray-Entfernung
dessen gesonderter
[Anleitung zur manuellen Entfernung](https://github.com/HT64/xucRun/blob/main/docs/de/MANUAL_REMOVAL.md).
