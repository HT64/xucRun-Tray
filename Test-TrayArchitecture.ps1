# Purpose: Verifies the standalone Tray repository boundary and sibling Core references.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
$forbiddenDirectories = @(
    'xucRun',
    'xucRunApproval',
    'xucRunBroker',
    'xucRunClientCommon',
    'xucRunCore',
    'xucRunInstaller',
    'xucRunLanguageDeDe',
    'xucRunLanguageEnUs',
    'xucRunSharedResources'
)
foreach ($directory in $forbiddenDirectories) {
    $candidate = Join-Path $repositoryRoot $directory
    $copiedSources = @(
        Get-ChildItem -LiteralPath $candidate -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\x64\\' }
    )
    if ($copiedSources.Count -ne 0) {
        throw "Standalone Tray repository contains copied Core sources below '$directory'."
    }
}

$project = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\xucRunTray.vcxproj'))
foreach ($requiredReference in @(
    '$(XucRunCoreRoot)\xucRunCore\xucRunCore.vcxproj',
    '$(XucRunCoreRoot)\xucRunClientCommon\xucRunClientCommon.vcxproj',
    '$(XucRunCoreRoot)\xucRunSharedResources\ClientResources.rc'
)) {
    if (-not $project.Contains($requiredReference)) {
        throw "Tray project is missing sibling Core reference '$requiredReference'."
    }
}
if ($project -match '\.\.\\xucRun(Core|ClientCommon|SharedResources)') {
    throw 'Tray project still contains a legacy in-repository Core path.'
}

$trackedCandidates = @(
    Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Force |
        Where-Object {
            $_.FullName -notlike (Join-Path $repositoryRoot '.git\*') -and
            $_.FullName -notlike (Join-Path $repositoryRoot 'artifacts\*') -and
            $_.FullName -notmatch '\\x64\\'
        }
)
foreach ($file in $trackedCandidates) {
    if ($file.Extension -in @('.pfx', '.p12', '.pvk', '.key', '.pem', '.env')) {
        throw "Tray repository contains forbidden secret-bearing file '$($file.FullName)'."
    }
}

Write-Host 'xucRun standalone Tray architecture passed'
