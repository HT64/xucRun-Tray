<#
.SYNOPSIS
Creates an xucRun Tray payload or release package from built artifacts.

.DESCRIPTION
Verifies the pinned sibling xucRun checkout against Dependencies.json, reads
the shared product and protocol versions, and packages Tray build outputs.
With SkipInstaller, it copies the executable, language assemblies, installer
and signing helper into a payload directory and writes TrayPackage.json with
SHA-256 hashes. Otherwise it verifies version and signing consistency between
the bootstrap installer and payload, copies the versioned installer plus
LICENSE and NOTICE, and writes SHA256SUMS.json.

.PARAMETER Configuration
Build configuration whose artifacts are packaged. Allowed values are Debug
and Release; the default is Release.

.PARAMETER DestinationDirectory
Output directory. If omitted or blank, the default is
artifacts\Payload\<Configuration> with SkipInstaller and
artifacts\Package\<Configuration> otherwise. An existing destination is
deleted recursively before the package is written.

.PARAMETER SkipInstaller
Creates only the embedded payload and manifest instead of the public release
package. Defaults to false.

.PARAMETER SignPayloadScript
Runs the script identified by SignScriptPath against the staged
Install-xucRunTray.ps1 before hashing the payload. Defaults to false and is
permitted only with SkipInstaller.

.PARAMETER SignScriptPath
Path to the signing script used when SignPayloadScript is set. It has no
default and must name an existing file when signing is requested.

.EXAMPLE
.\New-xucRunTray-Package.ps1 -Configuration Release -SkipInstaller

Recreates the default Release payload and its TrayPackage.json manifest from
the Release build artifacts.

.NOTES
Requires PowerShell, Git, the pinned sibling xucRun checkout, a valid
Dependencies.json, and already-built matching Tray artifacts. Authenticode
inspection is performed for release packaging. The command removes and
recreates its destination, so that location must not contain unrelated data.
It does not sign binaries; optional signing applies only to the staged
installer script through the explicitly supplied helper. Normal completion
returns 0 when run with powershell.exe -File. Missing or mismatched
dependencies, artifacts, versions, signatures, legal files, or a failed
signing helper cause a terminating error and a nonzero process exit code.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$DestinationDirectory,
    [switch]$SkipInstaller,
    [switch]$SignPayloadScript,
    [string]$SignScriptPath
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

if ($SignPayloadScript -and -not $SkipInstaller) {
    throw 'SignPayloadScript is supported only when creating the embedded payload.'
}
if ($SignPayloadScript -and
    (-not $SignScriptPath -or
        -not (Test-Path -LiteralPath $SignScriptPath -PathType Leaf))) {
    throw 'SignPayloadScript requires an existing SignScriptPath.'
}

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
    if ($SignPayloadScript) {
        powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $SignScriptPath `
            -Path (Join-Path $destination 'Install-xucRunTray.ps1')
        if ($LASTEXITCODE -ne 0) {
            throw 'Signing the staged Tray installer script failed.'
        }
    }
    $manifestFiles = @(
        foreach ($relativePath in @(
            'xucRunTray.exe',
            'Languages\xucRunTray.de-DE.dll',
            'Languages\xucRunTray.en-US.dll',
            'Install-xucRunTray.ps1'
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
        'Languages\xucRunTray.en-US.dll',
        'Install-xucRunTray.ps1'
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
