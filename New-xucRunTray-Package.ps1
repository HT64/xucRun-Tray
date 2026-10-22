# Purpose: Creates the internal payload or complete public release package for xucRun Tray.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$DestinationDirectory,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
$coreRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '..\xucRun-Core'))
$sourceRoot = Join-Path $repositoryRoot "artifacts\$Configuration"
$payloadRoot = Join-Path $repositoryRoot "artifacts\Payload\$Configuration"
$packageRoot = Join-Path $repositoryRoot "artifacts\Package\$Configuration"
$versionHeaderPath = Join-Path $coreRoot 'xucRunSharedResources\BuildVersion.h'
$contractsPath = Join-Path $coreRoot 'xucRunCore\BrokerContracts.h'
$dependenciesPath = Join-Path $repositoryRoot 'Dependencies.json'

if (-not (Test-Path -LiteralPath $versionHeaderPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $contractsPath -PathType Leaf)) {
    throw "The pinned sibling xucRun checkout is incomplete: $coreRoot"
}
if (-not (Test-Path -LiteralPath $dependenciesPath -PathType Leaf)) {
    throw "Tray dependency contract is missing: $dependenciesPath"
}
$dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
if ($dependencies.schemaVersion -ne 1 -or
    $dependencies.core.repository -ne 'HT64/xucRun' -or
    $dependencies.core.commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Dependencies.json does not contain a valid xucRun dependency.'
}
$coreCommit = (& git -c "safe.directory=$coreRoot" -C $coreRoot rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0 -or $coreCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Could not determine the pinned xucRun commit: $coreCommit"
}
$coreCommit = $coreCommit.Trim()
if ($coreCommit -ne $dependencies.core.commit) {
    throw "xucRun is at $coreCommit; expected $($dependencies.core.commit)."
}
$versionHeader = [IO.File]::ReadAllText($versionHeaderPath)
if ($versionHeader -notmatch '#define VERSION_STRING "(\d+\.\d+\.\d+\.\d+)"') {
    throw 'Pinned xucRun BuildVersion.h does not contain a four-part VERSION_STRING.'
}
$productVersion = $matches[1]

if ($SkipInstaller) {
    $destination = if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
        $payloadRoot
    } else {
        [IO.Path]::GetFullPath($DestinationDirectory)
    }
    $contracts = [IO.File]::ReadAllText($contractsPath)
    if ($contracts -notmatch 'ProtocolVersion\s*=\s*(\d+)\s*;') {
        throw 'Pinned xucRun BrokerContracts.h does not contain ProtocolVersion.'
    }
    $protocolVersion = [int]$matches[1]
    $payloadFiles = [ordered]@{
        'xucRunTray.exe' = Join-Path $sourceRoot 'xucRunTray.exe'
        'Languages\xucRunTray.de-DE.dll' =
            Join-Path $sourceRoot 'Languages\xucRunTray.de-DE.dll'
        'Languages\xucRunTray.en-US.dll' =
            Join-Path $sourceRoot 'Languages\xucRunTray.en-US.dll'
        'Install-xucRunTray.ps1' =
            Join-Path $repositoryRoot 'Install-xucRunTray.ps1'
        'Sign-xucRunTrayPackage.ps1' =
            Join-Path $repositoryRoot 'Sign-xucRunTrayPackage.ps1'
    }
    foreach ($entry in $payloadFiles.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Tray payload file is missing: $($entry.Value)"
        }
    }
    $actualVersion = (Get-Item -LiteralPath $payloadFiles['xucRunTray.exe']).
        VersionInfo.ProductVersion
    if ($actualVersion -ne $productVersion) {
        throw "Tray payload has version '$actualVersion'; expected '$productVersion'."
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination | Out-Null
    foreach ($entry in $payloadFiles.GetEnumerator()) {
        $target = Join-Path $destination $entry.Key
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
            -Force | Out-Null
        Copy-Item -LiteralPath $entry.Value -Destination $target
    }
    $manifestFiles = @(
        foreach ($relativePath in @(
            'xucRunTray.exe',
            'Languages\xucRunTray.de-DE.dll',
            'Languages\xucRunTray.en-US.dll'
        )) {
            $path = Join-Path $destination $relativePath
            [ordered]@{
                path = $relativePath.Replace('\', '/')
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            }
        }
    )
    [ordered]@{
        schemaVersion = 1
        component = 'xucRun-Tray'
        productVersion = $productVersion
        requiredCoreProductVersion = $productVersion
        protocolVersion = $protocolVersion
        coreCommit = $coreCommit
        signingPolicy = 'same-as-installed-core'
        files = $manifestFiles
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $destination 'TrayPackage.json') `
            -Encoding UTF8
    Write-Host "xucRun Tray $Configuration payload created: $destination"
    return
}

$destination = if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
    $packageRoot
} else {
    [IO.Path]::GetFullPath($DestinationDirectory)
}
$installerSource = Join-Path $sourceRoot 'xucRunTray-Installer.exe'
if (-not (Test-Path -LiteralPath $installerSource -PathType Leaf)) {
    throw "Tray bootstrap installer is missing: $installerSource"
}
if ((Get-Item -LiteralPath $installerSource).VersionInfo.ProductVersion -ne
    $productVersion) {
    throw 'Tray bootstrap installer version does not match the xucRun version.'
}
$installerSignature = Get-AuthenticodeSignature -LiteralPath $installerSource
$payloadSignatures = @(
    foreach ($relativePath in @(
        'xucRunTray.exe',
        'Languages\xucRunTray.de-DE.dll',
        'Languages\xucRunTray.en-US.dll'
    )) {
        Get-AuthenticodeSignature -LiteralPath (Join-Path $payloadRoot $relativePath)
    }
)
if ($installerSignature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
    if (@($payloadSignatures | Where-Object {
        $_.Status -ne [Management.Automation.SignatureStatus]::NotSigned
    }).Count -ne 0) {
        throw 'An unsigned Tray installer must contain only unsigned payload files.'
    }
}
elseif ($installerSignature.Status.ToString() -in @('Valid', 'NotTrusted') -and
    $installerSignature.SignerCertificate) {
    if (@($payloadSignatures | Where-Object {
        $_.Status.ToString() -notin @('Valid', 'NotTrusted') -or
        -not $_.SignerCertificate -or
        $_.SignerCertificate.Thumbprint -ne
            $installerSignature.SignerCertificate.Thumbprint
    }).Count -ne 0) {
        throw 'A signed Tray installer must contain payload files signed by the same certificate.'
    }
}
else {
    throw "Tray installer signature is invalid: $($installerSignature.Status)"
}
if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination | Out-Null
$installerName = "xucRun-Tray-$productVersion-x64.exe"
$installerTarget = Join-Path $destination $installerName
Copy-Item -LiteralPath $installerSource -Destination $installerTarget
$checksums = [ordered]@{}
$checksums[$installerName] = (Get-FileHash -LiteralPath $installerTarget `
    -Algorithm SHA256).Hash
foreach ($legalFileName in @('LICENSE', 'NOTICE')) {
    $legalFileSource = Join-Path $repositoryRoot $legalFileName
    if (-not (Test-Path -LiteralPath $legalFileSource -PathType Leaf)) {
        throw "Required public release file is missing: $legalFileSource"
    }
    $legalFileTarget = Join-Path $destination $legalFileName
    Copy-Item -LiteralPath $legalFileSource -Destination $legalFileTarget
    $checksums[$legalFileName] = (Get-FileHash -LiteralPath $legalFileTarget `
        -Algorithm SHA256).Hash
}
$checksums | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.json') `
        -Encoding UTF8

Write-Host "xucRun Tray $Configuration release package created: $destination"
