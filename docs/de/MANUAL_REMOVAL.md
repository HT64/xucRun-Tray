# Manuelle Entfernung

**Sprache:** Deutsch | [English](../en/MANUAL_REMOVAL.md)

Dieses Dokument listet die von xucRun Tray angelegten Artefakte auf und beschreibt deren manuelle
Entfernung. Verwende dieses Verfahren nur, wenn die normale Tray-Deinstallation nicht
verwendet werden kann oder nicht erfolgreich abgeschlossen wird. Die normale Deinstallation ist
der bevorzugte und sicherere Weg.

Das Tray ist eine optionale Komponente von xucRun. Seine Entfernung darf weder den xucRun Core
noch Brokerdienst, Core-Konfiguration, Signaturzertifikat, gespeicherte Anmeldeinformationen,
Freigaben, Sicherungen oder Brokerdaten entfernen.

## Geltungsbereich

Das Verfahren entfernt die vom Tray installierten Dateien, Prozesse, geplanten Aufgaben und seinen
Deinstallationseintrag. Es löscht keine allgemeinen Windows-Historien wie
Aufgabenplanungsereignisse, Anwendungsereignisse, Prefetch, Amcache, Kompatibilitäts- oder
Zuletzt-verwendet-Daten, Wiederherstellungspunkte, externe Sicherungen oder Aufzeichnungen von
Sicherheits- und Verwaltungssoftware.

## Artefaktinventar

| Typ | Pfad oder Name | Hinweise |
|---|---|---|
| Tray-Programm | `%ProgramFiles%\xucRun\xucRunTray.exe` | Das Verzeichnis wird mit dem Core gemeinsam genutzt |
| Installationsskript | `%ProgramFiles%\xucRun\Install-xucRunTray.ps1` | Tray-spezifisch |
| Sprachdateien | `%ProgramFiles%\xucRun\Languages\xucRunTray.de-DE.dll` und `xucRunTray.en-US.dll` | Tray-spezifisch |
| Prozesse | `xucRunTray.exe` | In mehreren Benutzersitzungen kann jeweils eine Instanz laufen |
| Aufgabenordner | `\xucRun\` | Gemeinsam genutzter Ordner; nur entfernen, wenn er leer ist |
| Geplante Aufgaben | `BrokerStatus-<Benutzer-SID>` | Für jeden eingerichteten Windows-Benutzer kann eine Aufgabe bestehen |
| Deinstallationseintrag | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray` | Rechnerweit |
| Bereitstellungsrest | `%ProgramFiles%\xucRun\.xucRun-Tray-staging-<32 hexadezimale Zeichen>` | Wird normalerweise automatisch gelöscht |
| Sicherungsrest | `%ProgramFiles%\xucRun\.xucRun-Tray-backup-<32 hexadezimale Zeichen>` | Wird normalerweise automatisch gelöscht |
| Installer-Extraktion | `%ProgramData%\xucRun-Tray-Installer-<32 hexadezimale Zeichen>` | Wird normalerweise automatisch gelöscht |
| Installer-Diagnose | `%TEMP%\xucRun-Tray-Installer.log` | Wird bei Fehlern des grafischen Installers verwendet und normalerweise vor einem neuen Lauf entfernt |

Das Tray erzeugt weder ein Zertifikat noch einen Brokerdienst, Anmeldeinformationen, Freigaben
oder ein eigenes Produktdatenverzeichnis. Seine Deinstallationsdiagnose wird in das zum Core
gehörende Verzeichnis `%ProgramData%\xucRun\InstallerLogs` geschrieben. Entferne dieses
Verzeichnis nicht, solange der Core installiert bleibt.

## Verfahren zur manuellen Entfernung

Führe die folgenden Befehle in einem als Administrator gestarteten Windows PowerShell 5.1 aus.

### 1. Alle installierten Tray-Instanzen beenden

Der folgende Befehl beschränkt das Beenden auf Prozesse, die das installierte Tray-Programm
ausführen. Fremde Prozesse mit einem ähnlichen Namen werden nicht beendet:

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

Führe dies aus, solange alle Benutzersitzungen, in denen das Tray laufen kann, noch erreichbar
sind. Die Abfrage erfasst die für den erhöhten Administrator sichtbaren Prozesse aller Sitzungen.

### 2. Alle geplanten Tray-Aufgaben entfernen

```powershell
Get-ScheduledTask -TaskPath '\xucRun\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName.StartsWith('BrokerStatus-') } |
    Unregister-ScheduledTask -Confirm:$false
```

Jeder Aufgabenname enthält die SID des Windows-Benutzers, für den das Tray gestartet wird.
Entferne alle Aufgaben `BrokerStatus-<SID>`, nicht nur die Aufgabe des aktuell angemeldeten
Benutzers.

Entferne den Ordner `\xucRun\` nur, wenn er keine Aufgaben oder Unterordner mehr enthält:

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

Lösche den Ordner nicht, wenn ihn eine andere Aufgabe oder ein Unterordner verwendet.

### 3. Tray-Dateien entfernen

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

Lösche weder `%ProgramFiles%\xucRun` noch dessen Unterverzeichnis `Languages`, solange sie
Core-Dateien enthalten. Das Tray nutzt diese Verzeichnisse gemeinsam mit xucRun.

### 4. Tray-Deinstallationseintrag entfernen

```powershell
Remove-Item -LiteralPath `
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray' `
    -Recurse -Force -ErrorAction SilentlyContinue
```

Entferne nicht den separaten Eintrag `...\Uninstall\xucRun`, der zum Core gehört.

### 5. Reste abgebrochener Installationen prüfen

Prüfe die im Artefaktinventar genannten Pfade auf Bereitstellungs-, Sicherungs-, Extraktions-
oder Diagnosereste. Sie werden normalerweise automatisch gelöscht und sollten nur nach einem
Abbruch oder Fehler vorhanden sein.

Vor dem Löschen eines einzelnen Bereitstellungs- oder Sicherungsverzeichnisses:

1. Prüfe den vollständigen Namen einschließlich der 32 hexadezimalen Zeichen.
2. Prüfe, dass es ausschließlich Tray-Dateien des abgebrochenen Vorgangs enthält.
3. Stelle sicher, dass kein Installer mehr läuft.

Lösche weder `%ProgramFiles%\xucRun`, `%ProgramData%` noch `%TEMP%` rekursiv und verwende
keine weit gefasste Wildcard-Löschung. Ein Sicherungsverzeichnis kann die zuvor funktionsfähigen
Tray-Dateien enthalten; behalte es, bis die installierten Tray-Dateien geprüft oder
wiederhergestellt wurden.

Die feste Datei `%TEMP%\xucRun-Tray-Installer.log` gehört zu dem Windows-Konto, das den grafischen
Installer gestartet hat. Andere Konten können daher am jeweils aufgelösten Pfad eine eigene Datei
besitzen.

## Überprüfung

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

Bei erfolgreicher Überprüfung erscheinen weder Tray-Prozess noch `BrokerStatus-`-Aufgabe; alle fünf
`Test-Path`-Ergebnisse lauten `False`. Bleibt der Core installiert, müssen seine Dateien, sein
Dienst, seine Daten, sein Zertifikat, seine Anmeldeinformationen und sein Deinstallationseintrag
unverändert vorhanden sein.

Soll anschließend auch der Core entfernt werden, folge erst nach abgeschlossener Tray-Entfernung
dessen gesonderter
[Anleitung zur manuellen Entfernung](https://github.com/HT64/xucRun/blob/main/docs/de/MANUAL_REMOVAL.md).
