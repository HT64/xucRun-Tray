<!--
Purpose: Beschreibt das lokale Bauen und Paketieren von xucRun Tray.
Approach: Verwendet einen passenden Core-Schwester-Checkout und die vorhandenen Build- und Prüfskripte.
-->
# xucRun Tray bauen und paketieren

**Sprache:** Deutsch | [English](../en/BUILDING.md)

## Voraussetzungen

- ein x64-Windows-Buildsystem,
- Visual Studio 2022 oder Build Tools 2022 mit MSBuild und der Desktop-C++-Toolchain,
- ein Windows 10 SDK,
- ein Compiler mit C++20-Unterstützung,
- Windows PowerShell 5.1 für Paket- und Prüfskripte,
- ein zur `Dependencies.json` passender Core-Checkout.

Die Projekte verwenden das jeweils verfügbare Standard-MSVC-Toolset. Unterstützt werden nur die
x64-Konfigurationen `Debug` und `Release`.

Core und Tray müssen als Schwester-Checkouts vorliegen:

```text
repos\
├── xucRun-Core\
└── xucRun-Tray\
```

Der dokumentierte Build- und Paketablauf verwendet `..\xucRun-Core`.
`New-xucRunTray-Package.ps1` prüft, dass dieser Checkout der in `Dependencies.json` festgelegten
xucRun-Revision entspricht.

Alle Befehle in einer **Developer PowerShell for Visual Studio 2022** oder einer entsprechend
initialisierten Build-Tools-Umgebung im Stammverzeichnis des Tray-Repositorys ausführen.

## Debug-Build

```powershell
& MSBuild.exe .\XUCRun-Tray.sln `
  /t:Build /p:Configuration=Debug /p:Platform=x64 /m
```

## Release-Build

```powershell
& MSBuild.exe .\XUCRun-Tray.sln `
  /t:Build /p:Configuration=Release /p:Platform=x64 /m
```

## Toolchain-Bericht

Für einen Release-Build die tatsächlich verwendeten Versionen von Visual Studio, MSBuild, MSVC und
Windows SDK dauerhaft festhalten:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\New-BuildToolchainReport.ps1 `
  -ProjectPath .\xucRunTray\xucRunTray.vcxproj `
  -ProductName 'xucRun Tray' `
  -Configuration Release `
  -DestinationPath .\artifacts\BUILD-TOOLCHAIN.txt
```

Der Bericht wird in das vollständige Tray-Paket aufgenommen.

## Paket erstellen

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\New-xucRunTray-Package.ps1 `
  -Configuration Release `
  -BuildToolchainReportPath .\artifacts\BUILD-TOOLCHAIN.txt
```

Für ein Debug-Paket den Toolchain-Bericht mit `-Configuration Debug` erzeugen und beim Paketbefehl
ebenfalls `Debug` verwenden. Buildausgaben werden unter `artifacts\<Configuration>` und
vollständige Pakete unter `artifacts\Package\<Configuration>` geschrieben.

## Paket prüfen

Die Paketprüfung kontrolliert unter anderem Manifest, Dateien, Prüfsummen, Versionen,
PowerShell-Syntax und Installerverträge. Sie installiert oder signiert nichts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Test-TrayAddonPackage.ps1 `
  -Configuration Release
```
