# Purpose: Provides the localized graphical workflow for the xucRun Tray add-on installer.
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$InstallerPath,
    [Parameter(Mandatory)][string]$DiagnosticLogPath
)

$ErrorActionPreference = 'Stop'
trap {
    $details = ($_ | Out-String).Trim()
    try {
        Set-Content -LiteralPath $DiagnosticLogPath -Value $details `
            -Encoding UTF8
    }
    catch {
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show(
            $details, 'xucRun Tray Installer', 'OK', 'Error') | Out-Null
    }
    catch {
    }
    exit 1603
}
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
        Version = 'Paketversion'
        CoreVersion = 'Installierte xucRun-Version: {0} (kompatibel)'
        CoreCertificate = "Core-Zertifikat für die Tray-Signierung:`r`nName: {0}`r`nGültig seit: {1}   Gültig bis: {2}`r`nFingerabdruck: {3}"
        InstalledTray = "Installierte Tray-Version: {0}`r`nInstalliert/zuletzt aktualisiert: {1}"
        TrayNotInstalled = 'Es wurde keine vorhandene xucRun-Tray-Installation erkannt.'
        UnknownInstallTime = 'nicht verfügbar'
        User = 'Automatisch starten für'
        Install = 'Installieren'
        Cancel = 'Abbrechen'
        Ready = 'Bereit.'
        Working = 'Paket, xucRun-Version und Signaturen werden geprüft ...'
        Signing = 'Das Tray wird mit dem vorhandenen lokalen xucRun-Zertifikat signiert ...'
        Installing = 'Tray-Dateien und Anmeldeaufgabe werden eingerichtet ...'
        SuccessStarted = 'xucRun Tray wurde erfolgreich installiert und für {0} gestartet.'
        SuccessDeferred = 'xucRun Tray wurde erfolgreich installiert. Es startet für {0} bei der nächsten Anmeldung.'
        SuccessStartFailed = 'xucRun Tray wurde installiert, konnte aber nicht sofort für {0} gestartet werden. Es startet bei der nächsten Anmeldung.'
        CertificateSuccess = "`r`n`r`nDie Tray-Dateien wurden mit dem vorhandenen Core-Zertifikat signiert und installiert.`r`n`r`nName: {0}`r`nGültig seit: {1}`r`nGültig bis: {2}`r`nFingerabdruck: {3}"
        Failure = 'Die Installation ist fehlgeschlagen.'
        NoUsers = 'Es wurde kein auswählbares lokales Benutzerprofil gefunden.'
        CoreMissing = 'Eine unterstützte xucRun-Installation wurde nicht gefunden.'
        CoreVersionMismatch = 'Dieses Tray-Paket benötigt xucRun {0}. Installiert ist xucRun {1}.'
        CoreInvalid = 'Die installierte xucRun-Version besitzt keine passende, überprüfbare Signatur und Brokerbindung.'
        SignerMismatch = 'Die ursprünglichen Paketsignaturen stimmen nicht mit dem Installer überein.'
        Details = @'
Das Add-on setzt eine bereits installierte xucRun-Version mit exakt gleicher Produktversion
voraus. Vor Anzeige dieser Oberfläche wurden Version, Signatur und Brokerbindung geprüft. Tray und
xucRun müssen denselben vertrauenswürdigen Signierer verwenden.

Wenn xucRun bei der Installation mit einem rechnerlokalen Zertifikat neu signiert wurde,
verwendet dieser Installer denselben bereits vorhandenen, nicht exportierbaren privaten Schlüssel
für die drei Tray-Dateien.

Installiert werden ausschließlich xucRunTray.exe und die beiden Tray-Sprach-DLLs. xucRun,
Broker, gespeicherte Anmeldedaten und Freigaben werden nicht verändert. Die Deinstallation erfolgt
über den separaten Eintrag "xucRun Tray" in den Windows-Einstellungen.

Für jeden zusätzlichen lokalen Benutzer kann der Installer erneut ausgeführt und das betreffende
Konto ausgewählt werden. Bereits eingerichtete Benutzeraufgaben bleiben erhalten. Ist der neu
ausgewählte Benutzer angemeldet, startet sein Tray sofort; andernfalls bei seiner nächsten
Windows-Anmeldung. Für den Dateiaustausch kurzzeitig beendete Tray-Instanzen anderer Benutzer
werden anschließend wieder gestartet. Die Deinstallation entfernt die Aufgaben aller
eingerichteten Benutzer und bestätigt sichtbar, dass Core, Zertifikat, Anmeldedaten und Freigaben
unverändert geblieben sind.
'@
    }
    en = @{
        Title = 'Install xucRun Tray'
        Heading = 'Optional xucRun Tray add-on'
        Description = 'Installs the status and convenience interface matching the existing xucRun version.'
        Version = 'Package version'
        CoreVersion = 'Installed xucRun version: {0} (compatible)'
        CoreCertificate = "Core certificate used for Tray signing:`r`nName: {0}`r`nValid from: {1}   Valid until: {2}`r`nThumbprint: {3}"
        InstalledTray = "Installed Tray version: {0}`r`nInstalled/last updated: {1}"
        TrayNotInstalled = 'No existing xucRun Tray installation was detected.'
        UnknownInstallTime = 'not available'
        User = 'Start automatically for'
        Install = 'Install'
        Cancel = 'Cancel'
        Ready = 'Ready.'
        Working = 'Validating package, xucRun version, and signatures ...'
        Signing = 'Signing Tray with the existing local xucRun certificate ...'
        Installing = 'Installing Tray files and logon task ...'
        SuccessStarted = 'xucRun Tray was installed successfully and started for {0}.'
        SuccessDeferred = 'xucRun Tray was installed successfully. It will start for {0} at the next logon.'
        SuccessStartFailed = 'xucRun Tray was installed but could not be started immediately for {0}. It will start at the next logon.'
        CertificateSuccess = "`r`n`r`nThe Tray files were signed and installed with the existing Core certificate.`r`n`r`nName: {0}`r`nValid from: {1}`r`nValid until: {2}`r`nThumbprint: {3}"
        Failure = 'Installation failed.'
        NoUsers = 'No selectable local user profile was found.'
        CoreMissing = 'A supported xucRun installation was not found.'
        CoreVersionMismatch = 'This Tray package requires xucRun {0}. The installed version is xucRun {1}.'
        CoreInvalid = 'The installed xucRun version does not have a matching, verifiable signature and broker binding.'
        SignerMismatch = 'The original package signatures do not match the installer.'
        Details = @'
The add-on requires an installed xucRun with the exact same product version. Its version,
signature, and broker binding were validated before this interface was shown. Tray and xucRun
must use the same trusted signer.

If xucRun was re-signed with a machine-local certificate during installation, this installer uses
the same existing non-exportable private key for the three Tray files.

Only xucRunTray.exe and the two Tray language DLLs are installed. xucRun, the broker, stored
credentials and approvals are not changed. Remove the add-on through the separate "xucRun Tray"
entry in Windows Settings.

Run the installer again for each additional local user and select that account. Tasks already
configured for other users remain in place. If the newly selected user is signed in, their Tray
starts immediately; otherwise, it starts at their next Windows sign-in. Tray instances for other
users that were stopped briefly while replacing files are restarted afterwards. Uninstalling
removes the tasks for all configured users and visibly confirms that Core, the certificate,
credentials, and approvals remain unchanged.
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

function Test-PackageSignature {
    param([Parameter(Mandatory)]$Signature)

    if (-not $Signature.SignerCertificate) {
        return $false
    }
    if ($Signature.Status.ToString() -in @('Valid', 'NotTrusted')) {
        return $true
    }
    if ($Signature.Status -ne [Management.Automation.SignatureStatus]::UnknownError -or
        $Signature.SignerCertificate.Subject -ne
        $Signature.SignerCertificate.Issuer) {
        return $false
    }

    $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        $chain.ChainPolicy.ApplicationPolicy.Add(
            [Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $chain.ChainPolicy.RevocationMode =
            [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.VerificationFlags =
            [Security.Cryptography.X509Certificates.X509VerificationFlags]::
                AllowUnknownCertificateAuthority
        return $chain.Build($Signature.SignerCertificate) -and
            $chain.ChainElements.Count -eq 1 -and
            @($chain.ChainStatus | Where-Object {
                $_.Status -ne
                [Security.Cryptography.X509Certificates.X509ChainStatusFlags]::
                    UntrustedRoot
            }).Count -eq 0
    }
    finally {
        $chain.Dispose()
    }
}

function Get-PackageSignature {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -eq [Management.Automation.SignatureStatus]::NotSigned -and
        -not $signature.SignerCertificate) {
        return $signature
    }
    if (Test-PackageSignature -Signature $signature) {
        return $signature
    }
    throw "Signature validation failed: $Path ($($signature.Status))"
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

function Get-InstalledTrayState {
    $uninstallPath =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray'
    if (-not (Test-Path -LiteralPath $uninstallPath)) {
        return $null
    }

    $key = Get-Item -LiteralPath $uninstallPath
    $version = [string]$key.GetValue('DisplayVersion', '')
    if ([string]::IsNullOrWhiteSpace($version)) {
        return $null
    }

    $installedAt = [DateTimeOffset]::MinValue
    $timestamp = [string]$key.GetValue('InstallTimestampUtc', '')
    if (-not [DateTimeOffset]::TryParse(
        $timestamp,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$installedAt)) {
        $installLocation = [string]$key.GetValue('InstallLocation', '')
        $trayPath = Join-Path $installLocation 'xucRunTray.exe'
        $installedAt = if (Test-Path -LiteralPath $trayPath -PathType Leaf) {
            [DateTimeOffset](Get-Item -LiteralPath $trayPath).CreationTime
        } else {
            $null
        }
    }

    return [pscustomobject]@{
        Version = $version
        InstalledAt = $installedAt
    }
}

function Get-CompatibleCoreState {
    param(
        [Parameter(Mandatory)][string]$CorePath,
        [Parameter(Mandatory)]$Manifest
    )

    if (-not (Test-Path -LiteralPath $CorePath -PathType Leaf)) {
        throw $t.CoreMissing
    }
    $version = (Get-Item -LiteralPath $CorePath).VersionInfo.ProductVersion
    if ($version -ne $Manifest.requiredCoreProductVersion) {
        throw ($t.CoreVersionMismatch -f
            $Manifest.requiredCoreProductVersion, $version)
    }

    try {
        $signer = Get-Signer -Path $CorePath
        $parametersPath =
            'HKLM:\SYSTEM\CurrentControlSet\Services\xucRunBroker\Parameters'
        if (-not (Test-Path -LiteralPath $parametersPath)) {
            throw $t.CoreInvalid
        }
        $parameters = Get-Item -LiteralPath $parametersPath
        $registeredPath = [string]$parameters.GetValue(
            'SensitiveClientImagePath', '')
        $registeredSigner = $parameters.GetValue(
            'SensitiveClientSignerSha256', $null)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $actualSigner = $sha256.ComputeHash($signer.RawData)
        }
        finally {
            $sha256.Dispose()
        }
        if (-not [string]::Equals(
            [IO.Path]::GetFullPath($registeredPath),
            [IO.Path]::GetFullPath($CorePath),
            [StringComparison]::OrdinalIgnoreCase) -or
            $registeredSigner -isnot [byte[]] -or
            [Convert]::ToBase64String($registeredSigner) -ne
            [Convert]::ToBase64String($actualSigner)) {
            throw $t.CoreInvalid
        }
    }
    catch {
        if ($_.Exception.Message -eq $t.CoreInvalid) {
            throw
        }
        throw $t.CoreInvalid
    }

    return [pscustomobject]@{
        Version = $version
        Signer = $signer
    }
}

$manifest = Get-Content -LiteralPath (
    Join-Path $PackageDirectory 'TrayPackage.json') -Raw | ConvertFrom-Json
$programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
$installedCore = Join-Path $programFiles 'xucRun\xucRun.exe'
try {
    Assert-ManifestHashes -Manifest $manifest
    $coreState = Get-CompatibleCoreState -CorePath $installedCore `
        -Manifest $manifest
}
catch {
    [Windows.Forms.MessageBox]::Show(
        $_.Exception.Message, $t.Title, 'OK', 'Error') |
        Out-Null
    exit 1603
}
$users = @(Get-SelectableUsers)
if ($users.Count -eq 0) {
    [Windows.Forms.MessageBox]::Show($t.NoUsers, $t.Title, 'OK', 'Error') |
        Out-Null
    exit 1603
}
$installedTrayState = Get-InstalledTrayState
$certificateCulture = [Globalization.CultureInfo]::GetCultureInfo(
    $(if ($language -eq 'de') { 'de-DE' } else { 'en-US' }))
$certificateName = $coreState.Signer.GetNameInfo(
    [Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
$certificateArguments = @(
    $certificateName,
    $coreState.Signer.NotBefore.ToString('g', $certificateCulture),
    $coreState.Signer.NotAfter.ToString('g', $certificateCulture),
    $coreState.Signer.Thumbprint)

$form = [Windows.Forms.Form]::new()
$form.Text = $t.Title
$form.ClientSize = [Drawing.Size]::new(634, 530)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$heading = [Windows.Forms.Label]::new()
$heading.AutoSize = $true
$heading.Text = $t.Heading
$heading.Font = [Drawing.Font]::new(
    $form.Font.FontFamily, 15, [Drawing.FontStyle]::Bold)
$heading.Location = [Drawing.Point]::new(24, 20)
$heading.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($heading)
$description = [Windows.Forms.Label]::new()
$description.AutoSize = $true
$description.Text = $t.Description
$description.Location = [Drawing.Point]::new(24, 62)
$description.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($description)
$version = [Windows.Forms.Label]::new()
$version.AutoSize = $true
$version.Text = "$($t.Version): $($manifest.productVersion)"
$version.Location = [Drawing.Point]::new(24, 108)
$version.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($version)
$coreVersion = [Windows.Forms.Label]::new()
$coreVersion.AutoSize = $true
$coreVersion.Text = $t.CoreVersion -f $coreState.Version
$coreVersion.Location = [Drawing.Point]::new(24, 136)
$coreVersion.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($coreVersion)
$coreCertificate = [Windows.Forms.Label]::new()
$coreCertificate.AutoSize = $true
$coreCertificate.Text = $t.CoreCertificate -f $certificateArguments
$coreCertificate.Location = [Drawing.Point]::new(24, 164)
$coreCertificate.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($coreCertificate)
$installedTray = [Windows.Forms.Label]::new()
$installedTray.AutoSize = $true
$installedTray.Text = if ($installedTrayState) {
    $installedAtText = if ($installedTrayState.InstalledAt) {
        $installedTrayState.InstalledAt.ToLocalTime().ToString(
            'g', [Globalization.CultureInfo]::CurrentCulture)
    } else {
        $t.UnknownInstallTime
    }
    $t.InstalledTray -f $installedTrayState.Version, $installedAtText
} else {
    $t.TrayNotInstalled
}
$installedTray.Location = [Drawing.Point]::new(24, 240)
$installedTray.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($installedTray)
$userLabel = [Windows.Forms.Label]::new()
$userLabel.AutoSize = $true
$userLabel.Text = $t.User
$userLabel.Location = [Drawing.Point]::new(24, 292)
$userLabel.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($userLabel)
$userBox = [Windows.Forms.ComboBox]::new()
$userBox.DropDownStyle = 'DropDownList'
$userBox.DisplayMember = 'DisplayName'
$userBox.SetBounds(24, 318, 590, 28)
[void]$userBox.Items.AddRange($users)
$userBox.SelectedIndex = 0
$form.Controls.Add($userBox)
$details = [Windows.Forms.TextBox]::new()
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.Text = $t.Details
$details.SetBounds(24, 362, 590, 130)
$form.Controls.Add($details)
$status = [Windows.Forms.Label]::new()
$status.AutoSize = $true
$status.Text = $t.Ready
$status.Location = [Drawing.Point]::new(24, 504)
$status.MaximumSize = [Drawing.Size]::new(590, 0)
$form.Controls.Add($status)
$installButton = [Windows.Forms.Button]::new()
$installButton.Text = $t.Install
$installButton.SetBounds(414, 570, 96, 30)
$form.Controls.Add($installButton)
$cancelButton = [Windows.Forms.Button]::new()
$cancelButton.Text = $t.Cancel
$cancelButton.SetBounds(518, 570, 96, 30)
$cancelButton.Add_Click({ $form.Close() })
$form.Controls.Add($cancelButton)

function Update-InstallerLayout {
    $description.Top = $heading.Bottom + 12
    $version.Top = $description.Bottom + 18
    $coreVersion.Top = $version.Bottom + 8
    $coreCertificate.Top = $coreVersion.Bottom + 8
    $installedTray.Top = $coreCertificate.Bottom + 14
    $userLabel.Top = $installedTray.Bottom + 18
    $userBox.Top = $userLabel.Bottom + 4
    $details.Top = $userBox.Bottom + 14
    $status.Top = $details.Bottom + 12
    $installButton.Top = $status.Bottom + 18
    $cancelButton.Top = $installButton.Top
    $form.ClientSize = [Drawing.Size]::new(
        634, $installButton.Bottom + 16)
}

Update-InstallerLayout

$script:exitCode = 1602
$installButton.Add_Click({
    $installButton.Enabled = $false
    $cancelButton.Enabled = $false
    try {
        $status.Text = $t.Working
        [Windows.Forms.Application]::DoEvents()
        $coreSigner = $coreState.Signer
        $payloadPaths = @($manifest.files | ForEach-Object {
            Join-Path $PackageDirectory ($_.path -replace '/', '\')
        })
        $payloadSignatures = @($payloadPaths | ForEach-Object {
            Get-PackageSignature -Path $_
        })
        $requiresLocalSigning = @($payloadSignatures | Where-Object {
            -not $_.SignerCertificate -or
            $_.SignerCertificate.Thumbprint -ne $coreSigner.Thumbprint
        }).Count -ne 0
        if ($requiresLocalSigning) {
            $installerSignature = Get-PackageSignature -Path $InstallerPath
            $unsignedPayload = @($payloadSignatures | Where-Object {
                $_.Status -eq [Management.Automation.SignatureStatus]::NotSigned
            }).Count -eq $payloadSignatures.Count
            $publisherPayload = $installerSignature.SignerCertificate -and
                @($payloadSignatures | Where-Object {
                    -not $_.SignerCertificate -or
                    $_.SignerCertificate.Thumbprint -ne
                        $installerSignature.SignerCertificate.Thumbprint
                }).Count -eq 0
            if (-not $unsignedPayload -and -not $publisherPayload) {
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
            foreach ($payloadPath in $payloadPaths) {
                $payloadSigner = Get-Signer -Path $payloadPath
                if ($payloadSigner.Thumbprint -ne $coreSigner.Thumbprint) {
                    throw $t.SignerMismatch
                }
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
        $startDisposition = if ($installResult.Details -match
            '(?m)^XUCRUN_TRAY_START_DISPOSITION=(Started|Deferred|Failed)\s*$') {
            $Matches[1]
        } else {
            'Failed'
        }
        $status.Text = switch ($startDisposition) {
            'Started' { $t.SuccessStarted -f $selected.DisplayName }
            'Deferred' { $t.SuccessDeferred -f $selected.DisplayName }
            default { $t.SuccessStartFailed -f $selected.DisplayName }
        }
        $messageIcon = if ($startDisposition -eq 'Failed') {
            'Warning'
        } else {
            'Information'
        }
        $successMessage =
            $status.Text + ($t.CertificateSuccess -f $certificateArguments)
        [Windows.Forms.MessageBox]::Show(
            $successMessage, $t.Title, 'OK', $messageIcon) | Out-Null
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
