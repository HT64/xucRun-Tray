<#
.SYNOPSIS
Creates bilingual release notes for one xucRun Tray version.

.DESCRIPTION
Extracts the requested version section from the English and German changelogs,
validates the supplied SHA256SUMS.txt file for the matching installer and
build toolchain report, and writes UTF-8 release notes containing installation
notices, build provenance, both changelog sections, links, and SHA-256
checksums. Hard-wrapped changelog prose is joined for GitHub rendering while
Markdown block structure is preserved.

.PARAMETER Version
Release version. This mandatory value must contain exactly four dot-separated
numeric components.

.PARAMETER ChecksumPath
Path to the mandatory SHA256SUMS.txt input produced by
New-xucRunTray-Package.ps1. It must contain uppercase SHA-256 hashes for the
versioned installer and BUILD-TOOLCHAIN.txt.

.PARAMETER DestinationPath
Output file path. Its parent directory is created when necessary, and an
existing file is replaced.

.EXAMPLE
.\New-xucRunTray-ReleaseNotes.ps1 `
    -Version 0.9.1.8 `
    -ChecksumPath .\artifacts\Package\Release\SHA256SUMS.txt `
    -DestinationPath .\artifacts\Package\Release\RELEASE-NOTES.md

Creates release notes from the matching checksums and changelog sections.

.NOTES
The repository must contain matching nonempty sections in CHANGELOG.md and
CHANGELOG.de.md. The script writes only DestinationPath; it does not create,
update, or publish a GitHub Release. It validates checksum syntax and names but
does not independently hash release assets or establish the checksum file's
origin. The output file can be overwritten. Missing or malformed checksums,
missing or empty changelog sections, invalid paths, and write failures are
terminating errors. A powershell.exe -File invocation returns 0 on success and
nonzero on an unhandled error.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory)]
    [string]$ChecksumPath,

    [Parameter(Mandatory)]
    [string]$DestinationPath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot

function Get-ChangelogVersionBody {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ReleaseVersion
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Changelog is missing: $Path"
    }
    $text = [IO.File]::ReadAllText($Path)
    $pattern = '(?ms)^##\s+\[' + [regex]::Escape($ReleaseVersion) +
        '\]\s+-\s+\d{4}-\d{2}-\d{2}\s*\r?\n(?<Body>.*?)(?=^##\s+\[|^\[[^\]]+\]:|\z)'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw "Changelog section for version $ReleaseVersion is missing: $Path"
    }
    $body = $match.Groups['Body'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Changelog section for version $ReleaseVersion is empty: $Path"
    }
    return $body
}

function ConvertTo-UnwrappedMarkdown {
    param([Parameter(Mandatory)][string]$Text)

    $result = New-Object 'System.Collections.Generic.List[string]'
    $inFence = $false
    $canJoin = $false
    foreach ($line in ($Text -split '\r?\n')) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^(```|~~~)') {
            $inFence = -not $inFence
            $result.Add($line)
            $canJoin = $false
            continue
        }
        if ($inFence) {
            $result.Add($line)
            continue
        }
        if ($trimmed.Length -eq 0) {
            $result.Add('')
            $canJoin = $false
            continue
        }
        $startsBlock = $trimmed -match '^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|\|)'
        if ($canJoin -and -not $startsBlock) {
            $result[$result.Count - 1] += ' ' + $trimmed
        }
        else {
            $result.Add($line.TrimEnd())
        }
        $canJoin = $trimmed -notmatch '^(#{1,6}\s|\|)' -and
            $line -notmatch '(\s{2}|\\)$'
    }
    return ($result -join [Environment]::NewLine)
}

if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) {
    throw "Release checksum file is missing: $ChecksumPath"
}
$checksumText = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $ChecksumPath).ProviderPath).Trim()
$checksums = @{}
foreach ($line in ($checksumText -split '\r?\n')) {
    if ($line -notmatch '^([0-9A-F]{64})  (.+)$') {
        throw "Release checksum line is invalid: $line"
    }
    if ($checksums.ContainsKey($matches[2])) {
        throw "Release checksum file contains duplicate '$($matches[2])'."
    }
    $checksums[$matches[2]] = $matches[1]
}
$installerName = "xucRun-Tray-$Version-x64.exe"
foreach ($assetName in @($installerName, 'BUILD-TOOLCHAIN.txt')) {
    $hash = $checksums[$assetName]
    if ($hash -notmatch '^[0-9A-F]{64}$') {
        throw "Release checksums do not contain a valid hash for $assetName."
    }
}

$englishChanges = ConvertTo-UnwrappedMarkdown -Text (Get-ChangelogVersionBody `
    -Path (Join-Path $repositoryRoot 'CHANGELOG.md') `
    -ReleaseVersion $Version)
$germanChanges = ConvertTo-UnwrappedMarkdown -Text (Get-ChangelogVersionBody `
    -Path (Join-Path $repositoryRoot 'CHANGELOG.de.md') `
    -ReleaseVersion $Version)
$notes = @"
## Important notice / Wichtiger Hinweis

xucRun Tray is an open-source project. The provided installer is not Authenticode-signed. Windows may therefore report an unknown publisher when it is first started. Download the files only from this GitHub Release and compare the SHA-256 checksum before starting the installer.

xucRun Tray ist ein Open-Source-Projekt. Die bereitgestellte Installer-Datei ist nicht Authenticode-signiert. Windows kann deshalb beim ersten Start einen unbekannten Herausgeber melden. Laden Sie die Dateien ausschließlich aus diesem GitHub Release herunter und vergleichen Sie vor dem Start die SHA-256-Prüfsumme.

Install xucRun Tray only with xucRun $Version. Remove xucRun Tray before updating or uninstalling xucRun.

Installieren Sie xucRun Tray ausschließlich zusammen mit xucRun $Version. Entfernen Sie xucRun Tray, bevor xucRun aktualisiert oder deinstalliert wird.

## Build provenance / Build-Herkunft

The official release files were built and verified automatically from the tagged source on a fresh GitHub Actions runner, independently of the local development system. `BUILD-TOOLCHAIN.txt` records the build tools actually used. GitHub build provenance attestations are also available for the files.

Die offiziellen Release-Dateien wurden automatisiert aus dem getaggten Quellstand auf einem frischen GitHub-Actions-Runner und damit unabhängig vom lokalen Entwicklungssystem erstellt und geprüft. `BUILD-TOOLCHAIN.txt` dokumentiert die tatsächlich verwendeten Buildwerkzeuge. Für die Dateien steht außerdem ein GitHub-Herkunftsnachweis zur Verfügung.

## Release information

$englishChanges

Full [changelog](https://github.com/HT64/xucRun-Tray/blob/v$Version/CHANGELOG.md)

## Veröffentlichungsinformationen

$germanChanges

Vollständiges [Änderungsprotokoll](https://github.com/HT64/xucRun-Tray/blob/v$Version/CHANGELOG.de.md)

## SHA-256

~~~text
$checksumText
~~~
"@

$destinationFullPath = [IO.Path]::GetFullPath($DestinationPath)
$destinationDirectory = Split-Path -Parent $destinationFullPath
if (-not (Test-Path -LiteralPath $destinationDirectory)) {
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
}
[IO.File]::WriteAllText(
    $destinationFullPath,
    $notes.Trim() + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Host "Release notes created: $destinationFullPath"
