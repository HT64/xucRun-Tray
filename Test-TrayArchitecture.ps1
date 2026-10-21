# Purpose: Verifies the standalone Tray repository boundary and sibling xucRun references.
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
        throw "Standalone Tray repository contains copied xucRun sources below '$directory'."
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
        throw "Tray project is missing sibling xucRun reference '$requiredReference'."
    }
}
if ($project -match '\.\.\\xucRun(Core|ClientCommon|SharedResources)') {
    throw 'Tray project still contains a legacy in-repository xucRun path.'
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

$buildProperties = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Directory.Build.props'))
$buildTargets = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Directory.Build.targets'))
if (($buildProperties + $buildTargets) -match
    '(?i)XucRunDistributionRoot|xucRun-Distribution') {
    throw 'Public Tray build files must not reference the private Distribution repository.'
}
if (-not $buildTargets.Contains('$(XucRunSignScript)')) {
    throw 'Public Tray signing must use the explicitly supplied XucRunSignScript.'
}
foreach ($publicFile in @(
    'LICENSE',
    'NOTICE',
    'README.md',
    'README.de.md',
    'SECURITY.md',
    'SECURITY.de.md',
    'CONTRIBUTING.md',
    'CONTRIBUTING.de.md',
    'Test-PublicRepository.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $publicFile) -PathType Leaf)) {
        throw "Public Tray repository file is missing: $publicFile"
    }
}

$installerProject = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\xucRunTrayInstaller.vcxproj'))
foreach ($requiredContract in @(
    'New-xucRunTray-Package.ps1',
    'SignReleaseInstaller',
    'SignTrayArtifacts'
)) {
    if (-not $installerProject.Contains($requiredContract)) {
        throw "Tray installer project is missing contract '$requiredContract'."
    }
}
$machineInstaller = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Install-xucRunTray.ps1'))
foreach ($requiredContract in @(
    'same-as-installed-core',
    'requiredCoreProductVersion',
    'Register-ScheduledTask',
    'xucRun Tray'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray machine installer is missing contract '$requiredContract'."
    }
}

Write-Host 'xucRun standalone Tray architecture passed'
