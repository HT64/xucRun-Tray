# Purpose: Verifies the Tray add-on package contract without changing the local installation.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
$payloadRoot = Join-Path $repositoryRoot "artifacts\Payload\$Configuration"
$packageRoot = Join-Path $repositoryRoot "artifacts\Package\$Configuration"
$manifestPath = Join-Path $payloadRoot 'TrayPackage.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Tray package manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or
    $manifest.component -ne 'xucRun-Tray' -or
    $manifest.productVersion -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
    $manifest.requiredCoreProductVersion -ne $manifest.productVersion -or
    $manifest.protocolVersion -isnot [int] -or
    $manifest.coreCommit -notmatch '^[0-9a-f]{40}$' -or
    $manifest.signingPolicy -ne 'same-as-installed-core') {
    throw 'Tray package manifest contract is invalid.'
}
$expectedPayload = @(
    'xucRunTray.exe',
    'Languages/xucRunTray.de-DE.dll',
    'Languages/xucRunTray.en-US.dll'
)
$actualPayload = @($manifest.files.path | Sort-Object)
if (($actualPayload -join "`n") -ne (($expectedPayload | Sort-Object) -join "`n")) {
    throw "Tray package manifest has an unexpected payload: $($actualPayload -join ', ')"
}
foreach ($file in $manifest.files) {
    $path = Join-Path $payloadRoot ($file.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Manifested Tray file is missing: $path"
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
        throw "Manifested Tray hash is invalid: $($file.path)"
    }
    if ($file.path -eq 'xucRunTray.exe' -and
        (Get-Item -LiteralPath $path).VersionInfo.ProductVersion -ne
            $manifest.productVersion) {
        throw "Manifested Tray version is invalid: $($file.path)"
    }
}
foreach ($scriptName in @(
    'Install-xucRunTray.ps1',
    'Sign-xucRunTrayPackage.ps1',
    'xucRunTrayInstaller\Installer-Gui.ps1'
)) {
    $path = Join-Path $repositoryRoot $scriptName
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell parser error in '$scriptName': $($errors.Message -join '; ')"
    }
}
$installer = Join-Path $repositoryRoot (
    "artifacts\$Configuration\xucRunTray-Installer.exe")
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Tray bootstrap installer is missing: $installer"
}
if ((Get-Item -LiteralPath $installer).VersionInfo.ProductVersion -ne
    $manifest.productVersion) {
    throw 'Tray bootstrap installer version does not match the package manifest.'
}
$versionedInstaller = Join-Path $packageRoot (
    "xucRun-Tray-$($manifest.productVersion)-x64.exe")
if (-not (Test-Path -LiteralPath $versionedInstaller -PathType Leaf)) {
    throw "Versioned Tray bootstrap installer is missing: $versionedInstaller"
}
$checksums = Get-Content -LiteralPath (
    Join-Path $packageRoot 'SHA256SUMS.json') -Raw | ConvertFrom-Json
$installerName = Split-Path -Leaf $versionedInstaller
$expectedHash = $checksums.$installerName
if ($expectedHash -ne
    (Get-FileHash -LiteralPath $versionedInstaller -Algorithm SHA256).Hash) {
    throw 'Tray bootstrap installer checksum is invalid.'
}
foreach ($legalFileName in @('LICENSE', 'NOTICE')) {
    $legalFile = Join-Path $packageRoot $legalFileName
    if (-not (Test-Path -LiteralPath $legalFile -PathType Leaf)) {
        throw "Public Tray release is missing $legalFileName."
    }
    if ($checksums.$legalFileName -ne
        (Get-FileHash -LiteralPath $legalFile -Algorithm SHA256).Hash) {
        throw "Public Tray release checksum is invalid for $legalFileName."
    }
}
$publishedFiles = @(
    Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
        ForEach-Object {
            $_.FullName.Substring($packageRoot.Length).TrimStart('\')
        } | Sort-Object
)
$expectedPublishedFiles = @(
    $installerName,
    'LICENSE',
    'NOTICE',
    'SHA256SUMS.json'
) | Sort-Object
if (($publishedFiles -join "`n") -ne ($expectedPublishedFiles -join "`n")) {
    throw "Tray release package contains unexpected files: $($publishedFiles -join ', ')"
}

$installerScript = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Install-xucRunTray.ps1'))
foreach ($forbidden in @(
    'New-Service',
    'sc.exe create',
    'xucRunBroker.exe',
    'xucRunApproval.exe'
)) {
    if ($installerScript.Contains($forbidden)) {
        throw "Tray installer contains forbidden xucRun mutation '$forbidden'."
    }
}
if ($installerScript -match
    'New-ItemProperty[\s\S]{0,300}SensitiveClientSignerSha256') {
    throw 'Tray installer must not modify the xucRun broker signer binding.'
}
$coreInstaller = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot '..\xucRun-Core\Install-xucRun.ps1'))
foreach ($requiredContract in @(
    'xucRun Tray add-on is installed',
    'Remove xucRun Tray first',
    'exactly matching Tray version'
)) {
    if (-not $coreInstaller.Contains($requiredContract)) {
        throw "xucRun installer is missing Tray update contract '$requiredContract'."
    }
}

Write-Host "xucRun Tray add-on package contract passed: $($manifest.productVersion)"
