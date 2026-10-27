# Purpose: Verifies the Tray add-on package contract without changing the local installation.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$expectedCopyright =
    'Copyright (C) 2024-2026 G' + [char]0x00FC + 'nther Thrum'
$expectedNoticeCopyright =
    'Copyright 2024-2026 G' + [char]0x00FC + 'nther Thrum'
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
    'Languages/xucRunTray.en-US.dll',
    'Install-xucRunTray.ps1'
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
    if ($file.path -ne 'Install-xucRunTray.ps1') {
        $versionInfo = (Get-Item -LiteralPath $path).VersionInfo
        if ($versionInfo.CompanyName -ne 'HT64' -or
            $versionInfo.LegalCopyright -ne $expectedCopyright -or
            $versionInfo.FileVersion -ne $manifest.productVersion -or
            $versionInfo.ProductVersion -ne $manifest.productVersion -or
            [string]::IsNullOrWhiteSpace($versionInfo.FileDescription) -or
            [string]::IsNullOrWhiteSpace($versionInfo.OriginalFilename)) {
            throw "Manifested Tray file metadata is incomplete: $($file.path)"
        }
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
$machineInstaller = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Install-xucRunTray.ps1'))
$graphicalInstaller = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\Installer-Gui.ps1'))
foreach ($requiredContract in @('InstallDate', 'InstallTimestampUtc')) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray installation timestamp contract is missing '$requiredContract'."
    }
}
foreach ($requiredContract in @(
    'Get-InstalledTrayState',
    'Get-CompatibleCoreState',
    'InstallTimestampUtc',
    'InstalledTray',
    'CoreVersion',
    'CoreCertificate',
    'CertificateSuccess',
    'Installationssprache',
    'Installer language',
    '$languageCombo.Add_SelectedIndexChanged',
    '$script:certificateArguments = Get-CertificateArguments',
    'Update-Language'
)) {
    if (-not $graphicalInstaller.Contains($requiredContract)) {
        throw "Tray installer display contract is missing '$requiredContract'."
    }
}
foreach ($requiredContract in @(
    'Get-InstalledTrayProcessUserSids',
    '$runningTrayUserSids + $UserSid',
    'Start-StatusTaskIfUserLoggedOn -Sid $sid',
    "Relative = 'Install-xucRunTray.ps1'",
    'Get-FileHash -LiteralPath $file.Destination',
    'Get-ValidSignerHash -Path $file.Destination'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray process restart contract is missing '$requiredContract'."
    }
}
foreach ($requiredContract in @(
    'Show-TrayUninstallSuccess',
    'Write-TrayUninstallDiagnostic',
    'Show-TrayUninstallFailure',
    'InstallerLogs',
    '-WindowStyle Hidden',
    'Open log folder',
    'xucRun Tray wurde erfolgreich deinstalliert.',
    'xucRun Tray was uninstalled successfully.',
    'das lokale xucRun-Zertifikat',
    'stored credentials and approvals'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray uninstall confirmation contract is missing '$requiredContract'."
    }
}
$installer = Join-Path $repositoryRoot (
    "artifacts\$Configuration\xucRunTray-Installer.exe")
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Tray bootstrap installer is missing: $installer"
}
$installerVersionInfo = (Get-Item -LiteralPath $installer).VersionInfo
if ($installerVersionInfo.CompanyName -ne 'HT64' -or
    $installerVersionInfo.LegalCopyright -ne $expectedCopyright -or
    $installerVersionInfo.ProductVersion -ne $manifest.productVersion) {
    throw 'Tray bootstrap installer metadata does not match the package contract.'
}
$versionedInstaller = Join-Path $packageRoot (
    "xucRun-Tray-$($manifest.productVersion)-x64.exe")
if (-not (Test-Path -LiteralPath $versionedInstaller -PathType Leaf)) {
    throw "Versioned Tray bootstrap installer is missing: $versionedInstaller"
}
$installerSignature =
    Get-AuthenticodeSignature -LiteralPath $versionedInstaller
$payloadSignatures = @(
    foreach ($file in $manifest.files) {
        Get-AuthenticodeSignature -LiteralPath (
            Join-Path $payloadRoot ($file.path -replace '/', '\'))
    }
)
if ($installerSignature.Status -eq [Management.Automation.SignatureStatus]::NotSigned) {
    if (@($payloadSignatures | Where-Object {
        $_.Status -ne [Management.Automation.SignatureStatus]::NotSigned
    }).Count -ne 0) {
        throw 'Unsigned Tray package contains a signed payload file.'
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
        throw 'Signed Tray package does not use one certificate for installer and payload.'
    }
}
else {
    throw "Tray package installer signature is invalid: $($installerSignature.Status)"
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
    if ($legalFileName -eq 'NOTICE' -and
        -not ([IO.File]::ReadAllText($legalFile).Contains(
            $expectedNoticeCopyright))) {
        throw 'Tray release NOTICE does not identify the expected copyright holder.'
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
    'Assert-TrayCompatibleWithCorePackage',
    'registeredTrayVersion -ne $ProductVersion',
    'does not use the Core package signer'
)) {
    if (-not $coreInstaller.Contains($requiredContract)) {
        throw "xucRun installer is missing Tray update contract '$requiredContract'."
    }
}

Write-Host "xucRun Tray add-on package contract passed: $($manifest.productVersion)"
