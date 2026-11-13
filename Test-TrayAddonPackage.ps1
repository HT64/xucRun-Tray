<#
.SYNOPSIS
Tests the built xucRun Tray payload and release package contract.

.DESCRIPTION
Validates the selected payload manifest, file set, SHA-256 hashes, versions,
binary metadata, PowerShell syntax, installer behavior contracts, and
signature consistency. It also verifies the bootstrap installer and public
package contents, checks legal-file hashes and NOTICE attribution, exercises
legal-file validation, installation, rollback, and removal in an isolated
temporary directory with system operations mocked, rejects
forbidden Core mutation patterns in the Tray installer, and confirms that the
pinned sibling Core installer contains the required Tray update safeguards.
The test reads artifacts and source files without changing the installation.

.PARAMETER Configuration
Artifact configuration to test. Allowed values are Debug and Release; the
default is Release.

.EXAMPLE
.\Test-TrayAddonPackage.ps1 -Configuration Release

Validates the Release payload, bootstrap installer, public package, and
cross-repository update contracts.

.NOTES
Requires PowerShell, a complete previously built and packaged artifact set
for the selected configuration, and the pinned sibling xucRun checkout.
Authenticode status and Windows version-resource metadata are inspected.
The test has no installation side effects and does not sign or rewrite
artifacts; its temporary test directory is removed afterward. Normal
completion returns 0 when run with powershell.exe -File.
Any missing file, parser error, contract mismatch, unexpected package file,
invalid hash, metadata, version, or signature state causes a terminating
error and a nonzero process exit code.
#>
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
if ($manifest.schemaVersion -ne 2 -or
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
$expectedLegal = @('LICENSE', 'NOTICE')
$actualLegal = @($manifest.legalFiles.path | Sort-Object)
if (($actualLegal -join "`n") -ne (($expectedLegal | Sort-Object) -join "`n")) {
    throw "Tray package manifest has unexpected legal files: $($actualLegal -join ', ')"
}
foreach ($file in $manifest.legalFiles) {
    $path = Join-Path $payloadRoot $file.path
    $source = Join-Path $repositoryRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256 -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $file.sha256) {
        throw "Manifested Tray legal file is missing or invalid: $($file.path)"
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
foreach ($requiredContract in @(
    'InstallDate',
    'InstallTimestampUtc',
    '$installationContractVersion = 3',
    'InstallationContractVersion'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray installation timestamp contract is missing '$requiredContract'."
    }
}
foreach ($requiredContract in @(
    'Get-InitialInstallerLanguage',
    '$sessionUserSid\Control Panel\Desktop',
    '$sessionUserSid\Control Panel\International\User Profile',
    'PreferredUILanguages',
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

function Test-LegalFileLifecycle {
    param($Manifest, [string]$SourcePayloadRoot, [string]$InstallerScript)

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $InstallerScript, [ref]$tokens, [ref]$errors)
    foreach ($name in @('Assert-NotReparsePoint', 'Remove-Tray')) {
        $definition = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $name
        }, $true)
        if (-not $definition) {
            throw "Tray installer function is missing: $name"
        }
        Invoke-Expression $definition.Extent.Text
    }

    $validationStart = $InstallerScript.IndexOf('$payload = @(')
    $validationEnd = $InstallerScript.IndexOf(
        'Assert-SelectableUser -Sid $UserSid', $validationStart)
    $installStart = $InstallerScript.IndexOf('$staging = Join-Path $programFiles (')
    $installEnd = $InstallerScript.IndexOf(
        'Write-Host "xucRun Tray $($manifest.productVersion) installed', $installStart)
    if ($validationStart -lt 0 -or $validationEnd -lt $validationStart -or
        $installStart -lt 0 -or $installEnd -lt $installStart) {
        throw 'Tray installer payload lifecycle could not be located.'
    }
    $validation = $InstallerScript.Substring(
        $validationStart, $validationEnd - $validationStart)
    $installation = $InstallerScript.Substring(
        $installStart, $installEnd - $installStart)

    function Get-ValidSignerHash {
        param([string]$Path)
        if ((Split-Path -Leaf $Path) -in @('LICENSE', 'NOTICE',
            'LICENSE-xucRun-Tray.txt', 'NOTICE-xucRun-Tray.txt')) {
            throw 'Unsigned legal files must not be checked as signed payload.'
        }
        return 'test-signer'
    }
    function Get-InstalledTrayProcessUserSids { return @() }
    function Stop-InstalledTray {}
    function Remove-StatusTasks {}
    function Set-StatusTask {
        param([string]$Sid)
        if ($failTask) { throw 'Injected task failure' }
    }
    function Set-TrayUninstallRegistryAcl {}
    function New-ItemProperty {}
    function Start-StatusTaskIfUserLoggedOn { param([string]$Sid) return 'Deferred' }

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'xucRun-Tray-legal-test-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        $packageRoot = Join-Path $testRoot 'package'
        $programFiles = Join-Path $testRoot 'program-files'
        $installDirectory = Join-Path $programFiles 'xucRun'
        $languageDirectory = Join-Path $installDirectory 'Languages'
        $legalDirectory = Join-Path $installDirectory 'Licenses'
        $installedTray = Join-Path $installDirectory 'xucRunTray.exe'
        $installedInstaller = Join-Path $installDirectory 'Install-xucRunTray.ps1'
        $uninstallPath = Join-Path $testRoot 'uninstall-entry'
        $trayLanguageFiles = @('xucRunTray.de-DE.dll', 'xucRunTray.en-US.dll')
        $expectedSigner = 'test-signer'
        $UserSid = 'S-1-5-21-1-2-3-1001'
        $failTask = $false
        New-Item -ItemType Directory -Path $packageRoot, $languageDirectory -Force |
            Out-Null
        foreach ($file in @($Manifest.files) + @($Manifest.legalFiles)) {
            $relative = $file.path.Replace('/', '\')
            $target = Join-Path $packageRoot $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force |
                Out-Null
            Copy-Item -LiteralPath (Join-Path $SourcePayloadRoot $relative) `
                -Destination $target
        }

        foreach ($name in @('LICENSE', 'NOTICE')) {
            $path = Join-Path $packageRoot $name
            Remove-Item -LiteralPath $path
            $failure = $null
            try { Invoke-Expression $validation } catch { $failure = $_ }
            if (-not $failure -or $failure.Exception.Message -notmatch 'package file is missing') {
                throw "Missing $name was not rejected by the Tray installer."
            }
            [IO.File]::WriteAllText($path, 'tampered')
            $failure = $null
            try { Invoke-Expression $validation } catch { $failure = $_ }
            if (-not $failure -or $failure.Exception.Message -notmatch 'hash validation failed') {
                throw "Tampered $name was not rejected by the Tray installer."
            }
            Copy-Item -LiteralPath (Join-Path $SourcePayloadRoot $name) `
                -Destination $path -Force
        }

        Invoke-Expression $validation
        $failTask = $true
        $failure = $null
        try { Invoke-Expression $installation } catch { $failure = $_ }
        if (-not $failure -or $failure.Exception.Message -notmatch 'Injected task failure' -or
            (Test-Path -LiteralPath $legalDirectory)) {
            throw 'The simulated first installation did not roll back its new legal directory.'
        }
        $failTask = $false
        Invoke-Expression $installation
        foreach ($name in @('LICENSE', 'NOTICE')) {
            $installed = Join-Path $legalDirectory "$name-xucRun-Tray.txt"
            if ((Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath (Join-Path $packageRoot $name) -Algorithm SHA256).Hash) {
                throw "Tray installation did not install $name."
            }
            [IO.File]::WriteAllText($installed, 'before-migration')
            [IO.File]::WriteAllText(
                (Join-Path $installDirectory "$name-xucRun-Tray.txt"), 'legacy')
        }
        $failTask = $true
        $failure = $null
        try { Invoke-Expression $installation } catch { $failure = $_ }
        if (-not $failure -or $failure.Exception.Message -notmatch 'Injected task failure') {
            throw 'The simulated Tray migration failure was not reported.'
        }
        foreach ($name in @('LICENSE', 'NOTICE')) {
            if ([IO.File]::ReadAllText((Join-Path $legalDirectory "$name-xucRun-Tray.txt")) -ne
                    'before-migration' -or
                [IO.File]::ReadAllText((Join-Path $installDirectory "$name-xucRun-Tray.txt")) -ne
                    'legacy') {
                throw "Tray rollback did not restore both locations for $name."
            }
        }
        $failTask = $false
        Invoke-Expression $installation
        foreach ($name in @('LICENSE', 'NOTICE')) {
            $installed = Join-Path $legalDirectory "$name-xucRun-Tray.txt"
            if ((Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath (Join-Path $packageRoot $name) -Algorithm SHA256).Hash) {
                throw "Tray update did not replace $name."
            }
            if (Test-Path -LiteralPath (Join-Path $installDirectory "$name-xucRun-Tray.txt")) {
                throw "Tray update did not remove the legacy $name."
            }
            [IO.File]::WriteAllText($installed, 'before-rollback')
        }
        $failTask = $true
        $failure = $null
        try { Invoke-Expression $installation } catch { $failure = $_ }
        if (-not $failure -or $failure.Exception.Message -notmatch 'Injected task failure') {
            throw 'The simulated Tray installation failure was not reported.'
        }
        foreach ($name in @('LICENSE', 'NOTICE')) {
            $installed = Join-Path $legalDirectory "$name-xucRun-Tray.txt"
            if ([IO.File]::ReadAllText($installed) -ne 'before-rollback') {
                throw "Tray rollback did not restore $name."
            }
            [IO.File]::WriteAllText((Join-Path $legalDirectory "$name-xucRun.txt"), 'core')
            [IO.File]::WriteAllText((Join-Path $installDirectory "$name-xucRun-Tray.txt"), 'legacy')
        }
        Remove-Tray
        foreach ($name in @('LICENSE', 'NOTICE')) {
            if ((Test-Path -LiteralPath (Join-Path $legalDirectory "$name-xucRun-Tray.txt")) -or
                (Test-Path -LiteralPath (Join-Path $installDirectory "$name-xucRun-Tray.txt")) -or
                [IO.File]::ReadAllText((Join-Path $legalDirectory "$name-xucRun.txt")) -ne 'core') {
                throw "Tray removal did not preserve the separate Core $name."
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Test-LegalFileLifecycle -Manifest $manifest -SourcePayloadRoot $payloadRoot `
    -InstallerScript $installerScript

Write-Host "xucRun Tray add-on package contract passed: $($manifest.productVersion)"
