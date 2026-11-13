<#
.SYNOPSIS
Runs the localized graphical xucRun Tray installation workflow.

.DESCRIPTION
Validates the embedded package manifest and hashes, the installed xucRun
version, signer, and broker authorization, then displays a German or English
Windows Forms interface. It lists eligible local profiles, shows the Core
certificate and existing Tray state, and lets the user choose the installer
language and target account. Its initial language follows the Windows language
preferences of the interactive session user, including when UAC uses a different
administrator account. Settings, installation details, security information,
and the bundled license and notices are shown on separate tabs.
The information is available offline and requires acknowledgment for every
installation or update. A README link is opened through the desktop shell.
When required, it invokes the bundled signing
helper so the payload uses the installed Core identity, revalidates hashes,
and invokes the machine installer first for validation and then installation.

.PARAMETER PackageDirectory
Mandatory directory containing TrayPackage.json, LICENSE, NOTICE, the complete
payload, and Sign-xucRunTrayPackage.ps1. It is also used briefly for redirected
helper output, which is removed after each helper invocation.

.PARAMETER InstallerPath
Mandatory path to the bootstrap installer executable. Its package signature
is checked when local payload signing is required.

.PARAMETER DiagnosticLogPath
Mandatory path where an unhandled-error trap attempts to write diagnostic
details before showing an error dialog and exiting with code 1603.

.EXAMPLE
.\Installer-Gui.ps1 -PackageDirectory 'C:\ProgramData\xucRunTrayPackage' `
    -InstallerPath 'C:\Installers\xucRun-Tray.exe' `
    -DiagnosticLogPath 'C:\ProgramData\xucRunTray-install.log'

Opens the localized installer, validates the package and installed Core, and
allows an eligible local user to be selected.

.NOTES
Intended for an elevated Windows installer process and requires Windows
PowerShell, Windows Forms, CIM/WTS access, a supported installed xucRun, and
the bundled machine installer and signing helper. It may sign payload files
with the existing non-exportable local Core key, create short-lived output
logs in PackageDirectory, and install Tray files, registry data, and a logon
task through Install-xucRunTray.ps1. It does not modify Core or export keys.
Opening the README requires an available desktop shell and internet connection.
Exit code 0 means installation succeeded, 1602 means the user closed or
cancelled the dialog before success, and 1603 means an unhandled validation
or installation error; the error trap makes a best effort to write the
diagnostic log and show the failure.
#>
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

function Get-InitialInstallerLanguage {
    $sessionUserSid = Get-CurrentSessionUserSid
    if ($sessionUserSid) {
        foreach ($preference in @(
            @{
                SubKey = "$sessionUserSid\Control Panel\Desktop"
                Value = 'PreferredUILanguages'
            },
            @{
                SubKey = "$sessionUserSid\Control Panel\International\User Profile"
                Value = 'Languages'
            }
        )) {
            $key = [Microsoft.Win32.Registry]::Users.OpenSubKey($preference.SubKey)
            if (-not $key) {
                continue
            }
            try {
                $preferredLanguages = @($key.GetValue($preference.Value))
            }
            finally {
                $key.Dispose()
            }
            foreach ($cultureName in $preferredLanguages) {
                if (-not [string]::IsNullOrWhiteSpace($cultureName)) {
                    $culture = [Globalization.CultureInfo]::GetCultureInfo($cultureName)
                    return $(if ($culture.TwoLetterISOLanguageName -eq 'de') {
                        'de'
                    } else {
                        'en'
                    })
                }
            }
        }
    }

    return $(if (
        [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'de') {
        'de'
    } else {
        'en'
    })
}
$texts = @{
    de = @{
        Title = 'xucRun Tray installieren'
        Heading = 'Optionales xucRun Tray-Add-on'
        Description = 'Installiert die zur vorhandenen xucRun-Version passende Status- und Bedienoberfläche.'
        SettingsTab = 'Einstellungen'
        DetailsTab = 'Ablauf und Deinstallation'
        Language = 'Installationssprache'
        Version = 'Paketversion'
        CoreVersion = 'Installierte xucRun-Version: {0} (kompatibel)'
        CoreCertificate = "Core-Zertifikat für die Tray-Signierung:`r`nName: {0}`r`nGültig seit: {1}   Gültig bis: {2}`r`nFingerabdruck: {3}"
        InstalledTray = "Installierte Tray-Version: {0}`r`nInstalliert/zuletzt aktualisiert: {1}"
        TrayNotInstalled = 'Es wurde keine vorhandene xucRun-Tray-Installation erkannt.'
        UnknownInstallTime = 'nicht verfügbar'
        User = 'Automatisch starten für'
        CertificateGroup = 'Vertrauen und Codesignierung'
        Install = 'Installieren'
        Cancel = 'Abbrechen'
        SecurityTab = 'Sicherheitshinweise'
        LicenseTab = 'Lizenz'
        LicenseIntroduction = 'xucRun Tray ist Open Source und steht unter der Apache License 2.0. Der vollständige Lizenztext und die Urheberhinweise werden unten angezeigt.'
        Acknowledgment = 'Ich stimme den Lizenzbedingungen zu und habe die Sicherheitshinweise verstanden.'
        StatusNotice = 'xucRun Tray wird aktiv weiterentwickelt. Die Dokumentation beschreibt das vorgesehene Verhalten. Der aktuelle Stand kann Fehler enthalten, davon abweichen und sich ändern.'
        SecurityNotice = @'
xucRun Tray zeigt Statusinformationen an und ruft vorhandene Verwaltungsfunktionen von xucRun auf. Es erweitert oder ersetzt die Sicherheitsmechanismen von xucRun nicht. Aus den angezeigten Informationen lässt sich keine Garantie für die Sicherheit des Systems, der Anmeldedaten oder gestarteter Programme ableiten. Der Quellcode von xucRun Tray wird offengelegt, damit die eingesetzten technischen Maßnahmen, ihre Grenzen und die verbleibenden Risiken nachvollzogen und unabhängig geprüft werden können. Die Offenlegung allein ist jedoch weder eine Sicherheitsgarantie noch der Nachweis einer unabhängigen Sicherheitsprüfung. Der Einsatz erfolgt eigenverantwortlich. xucRun Tray sollte nur auf vertrauenswürdigen, selbst verwalteten Systemen ohne erhöhten Schutzbedarf eingesetzt werden. Für Voraussetzungen, Schutzmechanismen, Einsatzgrenzen und verbleibende Risiken beachte die Sicherheitshinweise im README von xucRun.

Diese Sicherheitshinweise erheben keinen Anspruch auf Vollständigkeit; nicht alle Risiken und Sicherheitslücken können vorausgesehen oder ausgeschlossen werden.

Soweit gesetzlich zulässig, übernehmen der Autor und die Mitwirkenden keine Haftung für Schäden, Datenverluste oder sonstige Folgen, die aus der Nutzung oder fehlerhaften Anwendung von xucRun Tray, aus Softwarefehlern oder Sicherheitslücken sowie durch Malware oder ein kompromittiertes System entstehen. Dies umfasst insbesondere den Verlust, die Offenlegung oder den Missbrauch von Anmeldedaten. Maßgeblich sind der Gewährleistungsausschluss und die Haftungsbegrenzung der Apache License 2.0.
'@
        ReadmeLink = 'Anwenderdokumentation auf GitHub öffnen'
        ReadmeUrl = 'https://github.com/HT64/xucRun-Tray/blob/main/README.de.md'
        ReadmeOpenFailed = 'Die README konnte nicht über den Windows-Desktop geöffnet werden. Öffnen Sie diese Adresse in Ihrem Browser:'
        LicenseReadFailed = 'Lizenztext oder Hinweise konnten nicht gelesen werden. Die Installation kann nicht fortgesetzt werden.'
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

Installiert werden xucRunTray.exe, die Tray-Sprach-DLLs, der Tray-Maschineninstaller sowie Lizenz
und NOTICE. xucRun, Broker, gespeicherte Anmeldedaten und Freigaben werden nicht verändert. Die
Deinstallation erfolgt über den separaten Eintrag "xucRun Tray" in den Windows-Einstellungen.

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
        Description = 'Installs the status and control interface matching the existing xucRun version.'
        SettingsTab = 'Settings'
        DetailsTab = 'Process and uninstallation'
        Language = 'Installer language'
        Version = 'Package version'
        CoreVersion = 'Installed xucRun version: {0} (compatible)'
        CoreCertificate = "Core certificate used for Tray signing:`r`nName: {0}`r`nValid from: {1}   Valid until: {2}`r`nThumbprint: {3}"
        InstalledTray = "Installed Tray version: {0}`r`nInstalled/last updated: {1}"
        TrayNotInstalled = 'No existing xucRun Tray installation was detected.'
        UnknownInstallTime = 'not available'
        User = 'Start automatically for'
        CertificateGroup = 'Trust and code signing'
        Install = 'Install'
        Cancel = 'Cancel'
        SecurityTab = 'Security information'
        LicenseTab = 'License'
        LicenseIntroduction = 'xucRun Tray is open source and is licensed under the Apache License 2.0. The complete license text and attribution notices are shown below.'
        Acknowledgment = 'I agree to the license terms and understand the security information.'
        StatusNotice = 'xucRun Tray is actively maintained and continues to evolve. The documentation describes the intended behavior. The current state may contain defects, differ from that behavior, and change.'
        SecurityNotice = @'
xucRun Tray displays status information and invokes existing xucRun management functions. It neither extends nor replaces xucRun's security mechanisms. The displayed information does not guarantee the security of the system, credentials, or launched programs. The source code of xucRun Tray is disclosed so that the implemented technical measures, their limits, and the remaining risks can be understood and independently reviewed. Disclosure alone is neither a security guarantee nor evidence of an independent security audit. Use xucRun Tray at your own responsibility. xucRun Tray should be used only on trusted, self-managed systems that do not require an elevated level of protection. For requirements, safeguards, operating limits, and remaining risks, follow the security guidance in the xucRun README.

These security notices are not exhaustive; not all risks and security vulnerabilities can be anticipated or ruled out.

To the extent permitted by law, the author and contributors accept no liability for damage, data loss, or other consequences arising from the use or incorrect use of xucRun Tray, software defects or security vulnerabilities, malware, or a compromised system. This includes, in particular, the loss, disclosure, or misuse of credentials. The disclaimer of warranty and limitation of liability in the Apache License 2.0 govern.
'@
        ReadmeLink = 'Open user documentation on GitHub'
        ReadmeUrl = 'https://github.com/HT64/xucRun-Tray/blob/main/README.md'
        ReadmeOpenFailed = 'The README could not be opened through the Windows desktop. Open this address in your browser:'
        LicenseReadFailed = 'The license text or notices could not be read. Installation cannot continue.'
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

The installer installs xucRunTray.exe, the Tray language DLLs, the Tray machine installer, and
LICENSE and NOTICE. xucRun, the broker, stored credentials and approvals are not changed. Remove
the add-on through the separate "xucRun Tray" entry in Windows Settings.

Run the installer again for each additional local user and select that account. Tasks already
configured for other users remain in place. If the newly selected user is signed in, their Tray
starts immediately; otherwise, it starts at their next Windows sign-in. Tray instances for other
users that were stopped briefly while replacing files are restarted afterwards. Uninstalling
removes the tasks for all configured users and visibly confirms that Core, the certificate,
credentials, and approvals remain unchanged.
'@
    }
}

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

function Get-WtsSessionValue {
    param(
        [Parameter(Mandatory)][int]$SessionId,
        [Parameter(Mandatory)][int]$InformationClass
    )

    if (-not ('Native.WtsSession' -as [type])) {
        Add-Type -Namespace Native -Name WtsSession -MemberDefinition @'
[DllImport("Wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool WTSQuerySessionInformation(
    IntPtr server, int sessionId, int informationClass,
    out IntPtr buffer, out int bytesReturned);

[DllImport("Wtsapi32.dll")]
public static extern void WTSFreeMemory(IntPtr buffer);
'@
    }

    $buffer = [IntPtr]::Zero
    $bytesReturned = 0
    if (-not [Native.WtsSession]::WTSQuerySessionInformation(
        [IntPtr]::Zero, $SessionId, $InformationClass,
        [ref]$buffer, [ref]$bytesReturned)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw [ComponentModel.Win32Exception]::new(
            $errorCode, 'The interactive Windows session could not be queried.')
    }
    try {
        if ($buffer -eq [IntPtr]::Zero -or $bytesReturned -le 2) {
            return ''
        }
        return [Runtime.InteropServices.Marshal]::PtrToStringUni($buffer)
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [Native.WtsSession]::WTSFreeMemory($buffer)
        }
    }
}

function Get-CurrentSessionUserSid {
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $userName = Get-WtsSessionValue -SessionId $sessionId -InformationClass 5
    if ([string]::IsNullOrWhiteSpace($userName)) {
        return $null
    }
    $domainName = Get-WtsSessionValue -SessionId $sessionId -InformationClass 7
    $accountName = if ([string]::IsNullOrWhiteSpace($domainName)) {
        $userName
    }
    else {
        "$domainName\$userName"
    }
    return [Security.Principal.NTAccount]::new($accountName).Translate(
        [Security.Principal.SecurityIdentifier]).Value
}

$script:language = Get-InitialInstallerLanguage
$script:installInProgress = $false
$script:t = $texts[$script:language]

try {
    $licenseText = [IO.File]::ReadAllText(
        (Join-Path $PackageDirectory 'LICENSE'), [Text.Encoding]::UTF8)
    $noticeText = [IO.File]::ReadAllText(
        (Join-Path $PackageDirectory 'NOTICE'), [Text.Encoding]::UTF8)
}
catch {
    throw "$($t.LicenseReadFailed)`r`n`r`n$($_.Exception.Message)"
}

function Invoke-HiddenPowerShell {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $systemDirectory = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::System)
    if ([string]::IsNullOrWhiteSpace($systemDirectory)) {
        throw 'The Windows system directory could not be resolved.'
    }
    $powershell = Join-Path $systemDirectory `
        'WindowsPowerShell\v1.0\powershell.exe'
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
    foreach ($file in @($Manifest.files) + @($Manifest.legalFiles)) {
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
$certificateName = $coreState.Signer.GetNameInfo(
    [Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)

function Get-SelectedCulture {
    return [Globalization.CultureInfo]::GetCultureInfo(
        $(if ($script:language -eq 'de') { 'de-DE' } else { 'en-US' }))
}

function Get-CertificateArguments {
    $culture = Get-SelectedCulture
    return @(
        $certificateName,
        $coreState.Signer.NotBefore.ToString('g', $culture),
        $coreState.Signer.NotAfter.ToString('g', $culture),
        $coreState.Signer.Thumbprint)
}

function Get-InstalledTrayText {
    if (-not $installedTrayState) {
        return $t.TrayNotInstalled
    }
    $installedAtText = if ($installedTrayState.InstalledAt) {
        $installedTrayState.InstalledAt.ToLocalTime().ToString(
            'g', (Get-SelectedCulture))
    } else {
        $t.UnknownInstallTime
    }
    return $t.InstalledTray -f $installedTrayState.Version, $installedAtText
}

$script:certificateArguments = Get-CertificateArguments

$form = [Windows.Forms.Form]::new()
$form.ClientSize = [Drawing.Size]::new(620, 545)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.StartPosition = 'CenterScreen'

$heading = [Windows.Forms.Label]::new()
$heading.Font = [Drawing.Font]::new('Segoe UI', 17, [Drawing.FontStyle]::Bold)
$heading.Location = [Drawing.Point]::new(28, 20)
$heading.Size = [Drawing.Size]::new(562, 38)
$form.Controls.Add($heading)

$description = [Windows.Forms.Label]::new()
$description.AutoSize = $true
$description.Location = [Drawing.Point]::new(30, 62)
$description.MaximumSize = [Drawing.Size]::new(560, 0)
$form.Controls.Add($description)

$tabs = [Windows.Forms.TabControl]::new()
$tabs.Location = [Drawing.Point]::new(28, 100)
$tabs.Size = [Drawing.Size]::new(562, 315)
$form.Controls.Add($tabs)
$settingsTab = [Windows.Forms.TabPage]::new()
$detailsTab = [Windows.Forms.TabPage]::new()
$securityTab = [Windows.Forms.TabPage]::new()
$licenseTab = [Windows.Forms.TabPage]::new()
$tabs.TabPages.AddRange(@($settingsTab, $detailsTab, $securityTab, $licenseTab))

$languageLabel = [Windows.Forms.Label]::new()
$languageLabel.Location = [Drawing.Point]::new(14, 18)
$languageLabel.Size = [Drawing.Size]::new(180, 24)
$settingsTab.Controls.Add($languageLabel)
$languageCombo = [Windows.Forms.ComboBox]::new()
$languageCombo.DropDownStyle = 'DropDownList'
$languageCombo.Location = [Drawing.Point]::new(210, 15)
$languageCombo.Size = [Drawing.Size]::new(326, 24)
[void]$languageCombo.Items.Add('Deutsch')
[void]$languageCombo.Items.Add('English')
$languageCombo.SelectedIndex = if ($script:language -eq 'de') { 0 } else { 1 }
$settingsTab.Controls.Add($languageCombo)

$userLabel = [Windows.Forms.Label]::new()
$userLabel.Location = [Drawing.Point]::new(14, 50)
$userLabel.Size = [Drawing.Size]::new(180, 24)
$settingsTab.Controls.Add($userLabel)
$userBox = [Windows.Forms.ComboBox]::new()
$userBox.DropDownStyle = 'DropDownList'
$userBox.DisplayMember = 'DisplayName'
$userBox.Location = [Drawing.Point]::new(210, 47)
$userBox.Size = [Drawing.Size]::new(326, 24)
[void]$userBox.Items.AddRange($users)
$preferredUserSid = Get-CurrentSessionUserSid
$preferredUserIndex = -1
if ($preferredUserSid) {
    for ($index = 0; $index -lt $users.Count; $index++) {
        if ($users[$index].Sid -eq $preferredUserSid) {
            $preferredUserIndex = $index
            break
        }
    }
}
if ($preferredUserIndex -lt 0) {
    $processUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    for ($index = 0; $index -lt $users.Count; $index++) {
        if ($users[$index].Sid -eq $processUserSid) {
            $preferredUserIndex = $index
            break
        }
    }
}
$userBox.SelectedIndex = if ($preferredUserIndex -ge 0) {
    $preferredUserIndex
}
else {
    0
}
$settingsTab.Controls.Add($userBox)

$version = [Windows.Forms.Label]::new()
$version.AutoSize = $true
$version.Location = [Drawing.Point]::new(14, 82)
$version.MaximumSize = [Drawing.Size]::new(522, 0)
$settingsTab.Controls.Add($version)
$coreVersion = [Windows.Forms.Label]::new()
$coreVersion.AutoSize = $true
$coreVersion.Location = [Drawing.Point]::new(14, 105)
$coreVersion.MaximumSize = [Drawing.Size]::new(522, 0)
$settingsTab.Controls.Add($coreVersion)

$certificateGroup = [Windows.Forms.GroupBox]::new()
$certificateGroup.Location = [Drawing.Point]::new(14, 130)
$certificateGroup.Size = [Drawing.Size]::new(522, 100)
$settingsTab.Controls.Add($certificateGroup)
$coreCertificate = [Windows.Forms.Label]::new()
$coreCertificate.AutoSize = $true
$coreCertificate.Location = [Drawing.Point]::new(18, 24)
$coreCertificate.MaximumSize = [Drawing.Size]::new(486, 0)
$certificateGroup.Controls.Add($coreCertificate)

$installedTray = [Windows.Forms.Label]::new()
$installedTray.AutoSize = $true
$installedTray.Location = [Drawing.Point]::new(14, 240)
$installedTray.MaximumSize = [Drawing.Size]::new(522, 0)
$settingsTab.Controls.Add($installedTray)

$details = [Windows.Forms.TextBox]::new()
$details.Location = [Drawing.Point]::new(10, 12)
$details.Size = [Drawing.Size]::new(534, 244)
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = 'Vertical'
$details.BackColor = [Drawing.SystemColors]::Window
$detailsTab.Controls.Add($details)

$securityDetails = [Windows.Forms.TextBox]::new()
$securityDetails.Location = [Drawing.Point]::new(10, 12)
$securityDetails.Size = [Drawing.Size]::new(522, 190)
$securityDetails.Multiline = $true
$securityDetails.ReadOnly = $true
$securityDetails.ScrollBars = 'Vertical'
$securityDetails.BackColor = [Drawing.SystemColors]::Window
$securityTab.Controls.Add($securityDetails)
$readmeLink = [Windows.Forms.LinkLabel]::new()
$readmeLink.AutoSize = $true
$readmeLink.Location = [Drawing.Point]::new(10, 100)
$securityTab.Controls.Add($readmeLink)

$licenseIntroduction = [Windows.Forms.Label]::new()
$licenseIntroduction.AutoSize = $true
$licenseIntroduction.Location = [Drawing.Point]::new(10, 12)
$licenseIntroduction.MaximumSize = [Drawing.Size]::new(522, 0)
$licenseTab.Controls.Add($licenseIntroduction)
$licenseDetails = [Windows.Forms.TextBox]::new()
$licenseDetails.Location = [Drawing.Point]::new(10, 12)
$licenseDetails.Size = [Drawing.Size]::new(522, 244)
$licenseDetails.Multiline = $true
$licenseDetails.ReadOnly = $true
$licenseDetails.ScrollBars = 'Vertical'
$licenseDetails.BackColor = [Drawing.SystemColors]::Window
$licenseDetails.Text = (($licenseText + "`n`nNOTICE`n`n" + $noticeText) `
    -replace "`r?`n", "`r`n")
$licenseTab.Controls.Add($licenseDetails)

$acknowledgment = [Windows.Forms.CheckBox]::new()
$acknowledgment.AutoSize = $true
$acknowledgment.Location = [Drawing.Point]::new(28, 420)
$acknowledgment.MaximumSize = [Drawing.Size]::new(562, 0)
$acknowledgment.Checked = $false
$form.Controls.Add($acknowledgment)

$status = [Windows.Forms.Label]::new()
$status.Location = [Drawing.Point]::new(28, 432)
$status.Size = [Drawing.Size]::new(562, 18)
$form.Controls.Add($status)
$progress = [Windows.Forms.ProgressBar]::new()
$progress.Location = [Drawing.Point]::new(28, 454)
$progress.Size = [Drawing.Size]::new(562, 18)
$progress.Style = 'Marquee'
$progress.Visible = $false
$form.Controls.Add($progress)
$installButton = [Windows.Forms.Button]::new()
$installButton.Location = [Drawing.Point]::new(378, 495)
$installButton.Size = [Drawing.Size]::new(102, 34)
$installButton.Enabled = $false
$form.AcceptButton = $installButton
$form.Controls.Add($installButton)
$cancelButton = [Windows.Forms.Button]::new()
$cancelButton.Location = [Drawing.Point]::new(488, 495)
$cancelButton.Size = [Drawing.Size]::new(102, 34)
$cancelButton.DialogResult = 'Cancel'
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

function Update-InstallerLayout {
    $tabs.Top = [Math]::Max(100, $description.Bottom + 8)
    $userLabel.Top = $languageCombo.Bottom + 8
    $userBox.Top = $userLabel.Top - 3
    $version.Top = [Math]::Max($userBox.Bottom, $userLabel.Bottom) + 8
    $coreVersion.Top = $version.Bottom + 8
    $certificateGroup.Top = $coreVersion.Bottom + 10
    $certificateGroup.Height = $coreCertificate.Bottom + 12
    $installedTray.Top = $certificateGroup.Bottom + 10
    $tabs.Height = [Math]::Max(315, $installedTray.Bottom + 38)
    $details.Height = $tabs.Height - 56
    $securityDetails.Height = $tabs.Height - 85
    $readmeLink.Top = $securityDetails.Bottom + 8
    $licenseDetails.Top = $licenseIntroduction.Bottom + 10
    $licenseDetails.Height = $tabs.Height - $licenseDetails.Top - 44
    $acknowledgment.Top = $tabs.Bottom + 12
    $status.Top = $acknowledgment.Bottom + 12
    $progress.Top = $status.Bottom + 4
    $installButton.Top = $progress.Bottom + 24
    $cancelButton.Top = $installButton.Top
    $form.ClientSize = [Drawing.Size]::new(
        620, $installButton.Bottom + 16)
}

function Update-Language {
    $script:t = $texts[$script:language]
    $script:certificateArguments = Get-CertificateArguments
    $form.Text = $t.Title
    $heading.Text = $t.Heading
    $description.Text = $t.Description
    $settingsTab.Text = $t.SettingsTab
    $detailsTab.Text = $t.DetailsTab
    $securityTab.Text = $t.SecurityTab
    $licenseTab.Text = $t.LicenseTab
    $licenseIntroduction.Text = $t.LicenseIntroduction
    $languageLabel.Text = $t.Language
    $version.Text = "$($t.Version): $($manifest.productVersion)"
    $coreVersion.Text = $t.CoreVersion -f $coreState.Version
    $certificateGroup.Text = $t.CertificateGroup
    $coreCertificate.Text = $t.CoreCertificate -f $certificateArguments
    $installedTray.Text = Get-InstalledTrayText
    $userLabel.Text = $t.User
    $details.Text = ($t.Details.Trim() -replace "`r?`n", "`r`n")
    $securityDetails.Text = (($t.StatusNotice.Trim() + "`r`n`r`n" +
        $t.SecurityNotice.Trim()) -replace "`r?`n", "`r`n")
    $readmeLink.Text = $t.ReadmeLink
    $acknowledgment.Text = $t.Acknowledgment
    $status.Text = $t.Ready
    $installButton.Text = $t.Install
    $cancelButton.Text = $t.Cancel
    Update-InstallerLayout
}

function Update-InstallAvailability {
    $installButton.Enabled = $acknowledgment.Checked -and
        -not $script:installInProgress
}

function Open-Readme {
    param([string]$Url)
    try {
        $shell = New-Object -ComObject Shell.Application
        $desktopHandle = 0
        $desktop = $shell.Windows().FindWindowSW(
            0, 0, 8, [ref]$desktopHandle, 1)
        if ($null -eq $desktop) {
            throw 'The Windows desktop shell is unavailable.'
        }
        $desktop.Document.Application.ShellExecute($Url, '', '', 'open', 1)
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            ($t.ReadmeOpenFailed + "`r`n`r`n" + $Url +
                "`r`n`r`n" + $_.Exception.Message),
            $t.Title, 'OK', 'Error') | Out-Null
    }
}

$acknowledgment.Add_CheckedChanged({ Update-InstallAvailability })
$readmeLink.Add_LinkClicked({ Open-Readme -Url $t.ReadmeUrl })
$languageCombo.Add_SelectedIndexChanged({
    $script:language = if ($languageCombo.SelectedIndex -eq 0) { 'de' } else { 'en' }
    Update-Language
})

Update-Language

$script:exitCode = 1602
$installButton.Add_Click({
    $script:installInProgress = $true
    Update-InstallAvailability
    $acknowledgment.Enabled = $false
    $cancelButton.Enabled = $false
    $languageCombo.Enabled = $false
    $userBox.Enabled = $false
    $progress.Visible = $true
    $form.UseWaitCursor = $true
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
        $script:installInProgress = $false
        $acknowledgment.Enabled = $true
        Update-InstallAvailability
        $cancelButton.Enabled = $true
        $languageCombo.Enabled = $true
        $userBox.Enabled = $true
        $progress.Visible = $false
        $form.UseWaitCursor = $false
    }
})

[void]$form.ShowDialog()
exit $script:exitCode
