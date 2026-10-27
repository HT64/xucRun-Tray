# Purpose: Re-signs the Tray payload with the installed xucRun signer's local private key.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$TimestampServer
)

$ErrorActionPreference = 'Stop'

function Assert-WindowsPowerShell {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Run this script with Windows PowerShell 5.1 (powershell.exe).'
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator rights are required to use the installed xucRun signing key.'
    }
}

function Get-ValidSigner {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
        -not $signature.SignerCertificate) {
        throw "The installed xucRun does not have a valid signature: $Path " +
            "($($signature.Status))"
    }
    return $signature.SignerCertificate
}

function New-ProtectedStagingDirectory {
    $programData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::CommonApplicationData)
    $path = Join-Path $programData (
        'xucRun-Tray-Signing-' + [Guid]::NewGuid().ToString('N'))
    $inheritance = [Security.AccessControl.InheritanceFlags](
        [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit)
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $administrators =
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administrators)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        [Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
        'FullControl', $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $administrators, 'FullControl', $inheritance, $propagation, $allow))
    New-Item -ItemType Directory -Path $path | Out-Null
    Set-Acl -LiteralPath $path -AclObject $acl
    return $path
}

Assert-WindowsPowerShell
Assert-Administrator
$packageRoot = (Resolve-Path -LiteralPath $PackageDirectory).ProviderPath
$programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
$installedCore = Join-Path $programFiles 'xucRun\xucRun.exe'
if (-not (Test-Path -LiteralPath $installedCore -PathType Leaf)) {
    throw "xucRun is not installed at the supported path: $installedCore"
}
$installedSigner = Get-ValidSigner -Path $installedCore
$certificates = @(Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert |
    Where-Object {
        $_.Thumbprint -eq $installedSigner.Thumbprint -and $_.HasPrivateKey
    })
if ($certificates.Count -ne 1) {
    throw 'The installed xucRun signer does not have one usable private key in ' +
        'Cert:\LocalMachine\My. Install a Tray package signed by the same publisher instead.'
}
$certificate = $certificates[0]
$relativePaths = @(
    'xucRunTray.exe',
    'Languages\xucRunTray.de-DE.dll',
    'Languages\xucRunTray.en-US.dll',
    'Install-xucRunTray.ps1'
)
$staging = New-ProtectedStagingDirectory
try {
    foreach ($relativePath in $relativePaths) {
        $source = Join-Path $packageRoot $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Tray payload file is missing: $source"
        }
        $target = Join-Path $staging $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
            -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
        $arguments = @{
            FilePath = $target
            Certificate = $certificate
            HashAlgorithm = 'SHA256'
            IncludeChain = 'All'
        }
        if (-not [string]::IsNullOrWhiteSpace($TimestampServer)) {
            $arguments.TimestampServer = $TimestampServer
        }
        $result = Set-AuthenticodeSignature @arguments
        if ($result.Status -ne [Management.Automation.SignatureStatus]::Valid) {
            throw "Local signing failed for '$relativePath': $($result.Status)"
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $target
        if (-not $signature.SignerCertificate -or
            $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
            throw "Local signature verification failed for '$relativePath'."
        }
    }
    foreach ($relativePath in $relativePaths) {
        Copy-Item -LiteralPath (Join-Path $staging $relativePath) `
            -Destination (Join-Path $packageRoot $relativePath) -Force
    }

    $manifestPath = Join-Path $packageRoot 'TrayPackage.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw |
        ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path = Join-Path $packageRoot ($file.path -replace '/', '\')
        $file.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $manifest | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Tray payload signed with installed xucRun signer: $($certificate.Thumbprint)"
