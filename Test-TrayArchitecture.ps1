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
    'Dependencies.json',
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
$dependencies = Get-Content -LiteralPath `
    (Join-Path $repositoryRoot 'Dependencies.json') -Raw |
    ConvertFrom-Json
if ($dependencies.schemaVersion -ne 1 -or
    $dependencies.core.repository -ne 'HT64/xucRun' -or
    $dependencies.core.commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Dependencies.json does not contain a valid xucRun dependency.'
}
$workflow = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot '.github\workflows\ci.yml'))
foreach ($requiredContract in @(
    'Dependencies.json',
    'steps.core_dependency.outputs.repository',
    'steps.core_dependency.outputs.commit'
)) {
    if (-not $workflow.Contains($requiredContract)) {
        throw "Tray CI is missing dependency contract '$requiredContract'."
    }
}
$packageScript = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'New-xucRunTray-Package.ps1'))
foreach ($requiredContract in @(
    'Dependencies.json',
    '$dependencies.core.commit',
    '$coreCommit -ne $dependencies.core.commit'
)) {
    if (-not $packageScript.Contains($requiredContract)) {
        throw "Tray package creation is missing dependency contract '$requiredContract'."
    }
}

$installerProject = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\xucRunTrayInstaller.vcxproj'))
foreach ($requiredContract in @(
    'New-xucRunTray-Package.ps1',
    'SignReleaseInstaller',
    'SignTrayArtifacts',
    'SignPayloadScript',
    'SignScriptPath'
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
    'Set-TrayUninstallRegistryAcl',
    'RegistrySecurity',
    "Relative = 'Install-xucRunTray.ps1'",
    'Get-FileHash -LiteralPath $file.Destination',
    'xucRun Tray'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray machine installer is missing contract '$requiredContract'."
    }
}

Write-Host 'xucRun standalone Tray architecture passed'
