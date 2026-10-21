# Purpose: Provides the localized graphical workflow for the xucRun Tray add-on installer.
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$language = if (
    [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'de') {
    'de'
} else {
    'en'
}
$texts = @{
    de = @{
        Title = 'xucRun Tray installieren'
        Heading = 'Optionales xucRun Tray-Add-on'
        Description = 'Installiert die zur vorhandenen xucRun-Version passende Status- und Komfortoberfläche.'
        Version = 'Version'
        User = 'Automatisch starten für'
        Install = 'Installieren'
        Cancel = 'Abbrechen'
        Ready = 'Bereit.'
        Working = 'Paket, xucRun-Version und Signaturen werden geprüft ...'
        Signing = 'Das Tray wird mit dem vorhandenen lokalen xucRun-Zertifikat signiert ...'
        Installing = 'Tray-Dateien und Anmeldeaufgabe werden eingerichtet ...'
        Success = 'xucRun Tray wurde erfolgreich installiert. Es startet für {0} bei der nächsten Anmeldung.'
        Failure = 'Die Installation ist fehlgeschlagen.'
        NoUsers = 'Es wurde kein auswählbares lokales Benutzerprofil gefunden.'
        CoreMissing = 'Eine unterstützte xucRun-Installation wurde nicht gefunden.'
        SignerMismatch = 'Die ursprünglichen Paketsignaturen stimmen nicht mit dem Installer überein.'
        Details = @'
Das Add-on setzt eine bereits installierte xucRun-Version mit exakt gleicher Produktversion
voraus. Tray und xucRun müssen denselben vertrauenswürdigen Signierer verwenden.

Wenn xucRun bei der Installation mit einem rechnerlokalen Zertifikat neu signiert wurde,
verwendet dieser Installer denselben bereits vorhandenen, nicht exportierbaren privaten Schlüssel
für die drei Tray-Dateien.

Installiert werden ausschließlich xucRunTray.exe und die beiden Tray-Sprach-DLLs. xucRun,
Broker, gespeicherte Anmeldedaten und Freigaben werden nicht verändert. Die Deinstallation erfolgt
über den separaten Eintrag "xucRun Tray" in den Windows-Einstellungen.
'@
    }
    en = @{
        Title = 'Install xucRun Tray'
        Heading = 'Optional xucRun Tray add-on'
        Description = 'Installs the status and convenience interface matching the existing xucRun version.'
        Version = 'Version'
        User = 'Start automatically for'
        Install = 'Install'
        Cancel = 'Cancel'
        Ready = 'Ready.'
        Working = 'Validating package, xucRun version, and signatures ...'
        Signing = 'Signing Tray with the existing local xucRun certificate ...'
        Installing = 'Installing Tray files and logon task ...'
        Success = 'xucRun Tray was installed successfully. It will start for {0} at the next logon.'
        Failure = 'Installation failed.'
        NoUsers = 'No selectable local user profile was found.'
        CoreMissing = 'A supported xucRun installation was not found.'
        SignerMismatch = 'The original package signatures do not match the installer.'
        Details = @'
The add-on requires an installed xucRun with the exact same product version. Tray and xucRun
must use the same trusted signer.

If xucRun was re-signed with a machine-local certificate during installation, this installer uses
the same existing non-exportable private key for the three Tray files.

Only xucRunTray.exe and the two Tray language DLLs are installed. xucRun, the broker, stored
credentials and approvals are not changed. Remove the add-on through the separate "xucRun Tray"
entry in Windows Settings.
'@
    }
}
$t = $texts[$language]

function Get-Signer {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowUntrusted
    )
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $allowed = if ($AllowUntrusted) {
        @('Valid', 'NotTrusted')
    } else {
        @('Valid')
    }
    if (-not $signature.SignerCertificate -or
        $signature.Status.ToString() -notin $allowed) {
        throw "Signature validation failed: $Path ($($signature.Status))"
    }
    return $signature.SignerCertificate
}

function Get-SelectableUsers {
    $profiles = @{}
    Get-CimInstance -ClassName Win32_UserProfile |
        Where-Object { -not $_.Special -and $_.LocalPath } |
        ForEach-Object { $profiles[$_.SID] = $_.LocalPath }
    return @(Get-CimInstance -ClassName Win32_UserAccount `
        -Filter 'LocalAccount=True AND Disabled=False' |
        Where-Object { $profiles.ContainsKey($_.SID) } |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName = "$($_.Domain)\$($_.Name)"
                Sid = $_.SID
            }
        } | Sort-Object DisplayName)
}

function Invoke-HiddenPowerShell {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $powershell = Join-Path $env:SystemRoot `
        'System32\WindowsPowerShell\v1.0\powershell.exe'
    $id = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $PackageDirectory "$id.stdout.log"
    $stderr = Join-Path $PackageDirectory "$id.stderr.log"
    try {
        $process = Start-Process -FilePath $powershell -ArgumentList $Arguments `
            -WindowStyle Hidden -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr -Wait -PassThru
        $details = @(
            if (Test-Path -LiteralPath $stderr) {
                Get-Content -LiteralPath $stderr -Raw
            }
            if (Test-Path -LiteralPath $stdout) {
                Get-Content -LiteralPath $stdout -Raw
            }
        ) -join "`r`n"
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Details = $details.Trim()
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force `
            -ErrorAction SilentlyContinue
    }
}

function Assert-ManifestHashes {
    param([Parameter(Mandatory)]$Manifest)
    foreach ($file in $Manifest.files) {
        $path = Join-Path $PackageDirectory ($file.path -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
            $file.sha256) {
            throw "Package hash validation failed: $($file.path)"
        }
    }
}

$manifest = Get-Content -LiteralPath (
    Join-Path $PackageDirectory 'TrayPackage.json') -Raw | ConvertFrom-Json
$programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
$installedCore = Join-Path $programFiles 'xucRun\xucRun.exe'
if (-not (Test-Path -LiteralPath $installedCore -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show($t.CoreMissing, $t.Title, 'OK', 'Error') |
        Out-Null
    exit 1603
}
$users = @(Get-SelectableUsers)
if ($users.Count -eq 0) {
    [Windows.Forms.MessageBox]::Show($t.NoUsers, $t.Title, 'OK', 'Error') |
        Out-Null
    exit 1603
}

$form = [Windows.Forms.Form]::new()
$form.Text = $t.Title
$form.Size = [Drawing.Size]::new(650, 500)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$heading = [Windows.Forms.Label]::new()
$heading.Text = $t.Heading
$heading.Font = [Drawing.Font]::new($form.Font.FontFamily, 15, 'Bold')
$heading.SetBounds(24, 20, 590, 34)
$form.Controls.Add($heading)
$description = [Windows.Forms.Label]::new()
$description.Text = $t.Description
$description.SetBounds(24, 62, 590, 38)
$form.Controls.Add($description)
$version = [Windows.Forms.Label]::new()
$version.Text = "$($t.Version): $($manifest.productVersion)"
$version.SetBounds(24, 108, 590, 24)
$form.Controls.Add($version)
$userLabel = [Windows.Forms.Label]::new()
$userLabel.Text = $t.User
$userLabel.SetBounds(24, 142, 590, 24)
$form.Controls.Add($userLabel)
$userBox = [Windows.Forms.ComboBox]::new()
$userBox.DropDownStyle = 'DropDownList'
$userBox.DisplayMember = 'DisplayName'
$userBox.SetBounds(24, 168, 590, 28)
[void]$userBox.Items.AddRange($users)
$userBox.SelectedIndex = 0
$form.Controls.Add($userBox)
$details = [Windows.Forms.TextBox]::new()
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Text = $t.Details
$details.SetBounds(24, 212, 590, 160)
$form.Controls.Add($details)
$status = [Windows.Forms.Label]::new()
$status.Text = $t.Ready
$status.SetBounds(24, 384, 590, 24)
$form.Controls.Add($status)
$installButton = [Windows.Forms.Button]::new()
$installButton.Text = $t.Install
$installButton.SetBounds(414, 420, 96, 30)
$form.Controls.Add($installButton)
$cancelButton = [Windows.Forms.Button]::new()
$cancelButton.Text = $t.Cancel
$cancelButton.SetBounds(518, 420, 96, 30)
$cancelButton.Add_Click({ $form.Close() })
$form.Controls.Add($cancelButton)

$script:exitCode = 1602
$installButton.Add_Click({
    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    try {
        $status.Text = $t.Working
        [Windows.Forms.Application]::DoEvents()
        Assert-ManifestHashes -Manifest $manifest
        $coreVersion = (Get-Item -LiteralPath $installedCore).VersionInfo.ProductVersion
        if ($coreVersion -ne $manifest.requiredCoreProductVersion) {
            throw "Installed xucRun version '$coreVersion' does not match required version " +
                "'$($manifest.requiredCoreProductVersion)'."
        }
        $coreSigner = Get-Signer -Path $installedCore
        $payloadPaths = @($manifest.files | ForEach-Object {
            Join-Path $PackageDirectory ($_.path -replace '/', '\')
        })
        $payloadSigners = @($payloadPaths | ForEach-Object {
            Get-Signer -Path $_ -AllowUntrusted
        })
        $requiresLocalSigning = @($payloadSigners | Where-Object {
            $_.Thumbprint -ne $coreSigner.Thumbprint
        }).Count -ne 0
        if ($requiresLocalSigning) {
            $installerSigner = Get-Signer -Path $InstallerPath -AllowUntrusted
            if (@($payloadSigners | Where-Object {
                $_.Thumbprint -ne $installerSigner.Thumbprint
            }).Count -ne 0) {
                throw $t.SignerMismatch
            }
            $status.Text = $t.Signing
            [Windows.Forms.Application]::DoEvents()
            $signResult = Invoke-HiddenPowerShell -Arguments @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                ('"' + (Join-Path $PackageDirectory `
                    'Sign-xucRunTrayPackage.ps1') + '"'),
                '-PackageDirectory', ('"' + $PackageDirectory + '"')
            )
            if ($signResult.ExitCode -ne 0) {
                throw "Local Tray signing failed.`r`n$($signResult.Details)"
            }
        }
        $status.Text = $t.Installing
        [Windows.Forms.Application]::DoEvents()
        $selected = $userBox.SelectedItem
        $installResult = Invoke-HiddenPowerShell -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            ('"' + (Join-Path $PackageDirectory 'Install-xucRunTray.ps1') + '"'),
            '-PackageDirectory', ('"' + $PackageDirectory + '"'),
            '-UserSid', ('"' + $selected.Sid + '"')
        )
        if ($installResult.ExitCode -ne 0) {
            throw "Tray installation failed.`r`n$($installResult.Details)"
        }
        $status.Text = $t.Success -f $selected.DisplayName
        [Windows.Forms.MessageBox]::Show(
            $status.Text, $t.Title, 'OK', 'Information') | Out-Null
        $script:exitCode = 0
        $form.Close()
    }
    catch {
        $status.Text = $t.Failure
        [Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, $t.Title, 'OK', 'Error') | Out-Null
        $installButton.Enabled = $true
        $cancelButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
exit $script:exitCode
