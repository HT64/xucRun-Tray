# Purpose: Creates an exact unsigned package for the optional xucRun Tray component.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$DestinationDirectory
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $DestinationDirectory = Join-Path $repositoryRoot `
        "artifacts\Package\$Configuration"
}
$destination = [IO.Path]::GetFullPath($DestinationDirectory)
$sourceRoot = Join-Path $repositoryRoot "artifacts\$Configuration"
$coreVersionHeader = Join-Path (Split-Path -Parent $repositoryRoot) `
    'xucRun-Core\xucRunSharedResources\BuildVersion.h'
if (-not (Test-Path -LiteralPath $coreVersionHeader -PathType Leaf)) {
    throw "Pinned Core version header is missing: $coreVersionHeader"
}
$versionHeader = [IO.File]::ReadAllText($coreVersionHeader)
if ($versionHeader -notmatch '#define VERSION_STRING "([^"]+)"') {
    throw 'Pinned Core BuildVersion.h does not contain VERSION_STRING.'
}
$expectedVersion = $matches[1]
$files = [ordered]@{
    'xucRunTray.exe' = 'xucRunTray.exe'
    'Languages\xucRunTray.de-DE.dll' = 'Languages\xucRunTray.de-DE.dll'
    'Languages\xucRunTray.en-US.dll' = 'Languages\xucRunTray.en-US.dll'
}

foreach ($relativePath in $files.Values) {
    $source = Join-Path $sourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Tray build output is missing: $source"
    }
    if ($relativePath -eq 'xucRunTray.exe') {
        $actualVersion = (Get-Item -LiteralPath $source).VersionInfo.ProductVersion
        if ($actualVersion -ne $expectedVersion) {
            throw "Tray output '$relativePath' has version '$actualVersion'; expected '$expectedVersion'."
        }
    }
}

if (Test-Path -LiteralPath $destination) {
    $unexpected = @(
        Get-ChildItem -LiteralPath $destination -Recurse -File |
            Where-Object {
                $relative = $_.FullName.Substring(
                    $destination.Length).TrimStart('\')
                $relative -notin @($files.Keys) -and
                $relative -ne 'SHA256SUMS.json'
            }
    )
    if ($unexpected.Count -ne 0) {
        throw "Tray package contains unexpected files: $($unexpected.FullName -join ', ')"
    }
}
else {
    New-Item -ItemType Directory -Path $destination | Out-Null
}

$hashes = [ordered]@{}
foreach ($entry in $files.GetEnumerator()) {
    $source = Join-Path $sourceRoot $entry.Value
    $target = Join-Path $destination $entry.Key
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
    $hashes[$entry.Key.Replace('\', '/')] =
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
}
$hashes | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.json') `
        -Encoding UTF8

Write-Host "xucRun Tray $Configuration package created: $destination"
