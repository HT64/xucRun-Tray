<!--
Purpose: Describes local building and packaging of xucRun Tray.
Approach: Uses a matching Core sibling checkout and the existing build and package-validation scripts.
-->
# Build and package xucRun Tray

**Language:** [Deutsch](../de/BUILDING.md) | English

## Prerequisites

- an x64 Windows build system,
- Visual Studio 2022 or Build Tools 2022 with MSBuild and the Desktop C++ toolchain,
- a Windows 10 SDK,
- a compiler with C++20 support,
- Windows PowerShell 5.1 for package and validation scripts,
- a Core checkout matching `Dependencies.json`.

The projects use the available default MSVC toolset. Only the `Debug` and `Release` x64
configurations are supported.

Core and Tray must be available as sibling checkouts:

```text
repos\
├── xucRun-Core\
└── xucRun-Tray\
```

The documented build and package workflow uses `..\xucRun-Core`.
`New-xucRunTray-Package.ps1` verifies that this checkout matches the xucRun revision pinned in
`Dependencies.json`.

Run all commands from the Tray repository root in **Developer PowerShell for Visual Studio 2022**
or an equivalently initialized Build Tools environment.

## Debug build

```powershell
& MSBuild.exe .\XUCRun-Tray.sln `
  /t:Build /p:Configuration=Debug /p:Platform=x64 /m
```

## Release build

```powershell
& MSBuild.exe .\XUCRun-Tray.sln `
  /t:Build /p:Configuration=Release /p:Platform=x64 /m
```

## Toolchain report

For a release build, durably record the exact Visual Studio, MSBuild, MSVC, and Windows SDK
versions used:

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\New-BuildToolchainReport.ps1 `
  -ProjectPath .\xucRunTray\xucRunTray.vcxproj `
  -ProductName 'xucRun Tray' `
  -Configuration Release `
  -DestinationPath .\artifacts\BUILD-TOOLCHAIN.txt
```

The report is included in the complete Tray package.

## Create the package

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\New-xucRunTray-Package.ps1 `
  -Configuration Release `
  -BuildToolchainReportPath .\artifacts\BUILD-TOOLCHAIN.txt
```

To create a Debug package, generate the toolchain report with `-Configuration Debug` and also use
`Debug` in the package command. Build outputs are written below `artifacts\<Configuration>` and
complete packages below `artifacts\Package\<Configuration>`.

## Validate the package

The package validation checks the manifest, files, hashes, versions, PowerShell syntax, and
installer contracts, among other properties. It neither installs nor signs anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Test-TrayAddonPackage.ps1 `
  -Configuration Release
```
