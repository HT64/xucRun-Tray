# Purpose: Installs, updates, or removes the optional Tray add-on without changing xucRun.
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [string]$PackageDirectory,
    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [string]$UserSid,
    [Parameter(ParameterSetName = 'Install')]
    [switch]$ValidateOnly,
    [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles)
$installDirectory = Join-Path $programFiles 'xucRun'
$languageDirectory = Join-Path $installDirectory 'Languages'
$installedCore = Join-Path $installDirectory 'xucRun.exe'
$installedTray = Join-Path $installDirectory 'xucRunTray.exe'
$installedInstaller = Join-Path $installDirectory 'Install-xucRunTray.ps1'
$trayLanguageFiles = @('xucRunTray.de-DE.dll', 'xucRunTray.en-US.dll')
$taskPath = '\xucRun\'
$taskPrefix = 'BrokerStatus-'
$uninstallPath =
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun Tray'
$coreUninstallPath =
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\xucRun'
$coreParametersPath =
    'HKLM:\SYSTEM\CurrentControlSet\Services\xucRunBroker\Parameters'
$installerLogDirectory = Join-Path $env:ProgramData 'xucRun\InstallerLogs'

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
        throw 'Administrator rights are required to install or remove xucRun Tray.'
    }
}

function Assert-NotReparsePoint {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed for the Tray installation: $Path"
        }
    }
}

function Get-ValidSignerHash {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
        -not $signature.SignerCertificate) {
        throw "A valid trusted signature is required: $Path ($($signature.Status))"
    }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String(
            $sha256.ComputeHash($signature.SignerCertificate.RawData))
    }
    finally {
        $sha256.Dispose()
    }
}

function Stop-InstalledTray {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='xucRunTray.exe'" |
        Where-Object {
            $_.ExecutablePath -and
            [string]::Equals($_.ExecutablePath, $installedTray,
                [StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        }
}

function Initialize-TaskFolder {
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    try {
        [void]$scheduler.GetFolder('\').GetFolder('xucRun')
    }
    catch {
        if ($_.Exception.HResult -notin @(-2147024894, -2147024893)) {
            throw
        }
        [void]$scheduler.GetFolder('\').CreateFolder('xucRun')
    }
}

function Set-TrayUninstallRegistryAcl {
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $administratorsSid =
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $usersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl = [Security.AccessControl.RegistrySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administratorsSid)
    $acl.AddAccessRule([Security.AccessControl.RegistryAccessRule]::new(
        $systemSid, 'FullControl', $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.RegistryAccessRule]::new(
        $administratorsSid, 'FullControl', $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.RegistryAccessRule]::new(
        $usersSid, 'ReadKey', $inheritance, $propagation, $allow))
    Set-Acl -LiteralPath $uninstallPath -AclObject $acl
}

function Assert-SelectableUser {
    param([Parameter(Mandatory)][string]$Sid)

    $securityIdentifier = [Security.Principal.SecurityIdentifier]::new($Sid)
    [void]$securityIdentifier.Translate([Security.Principal.NTAccount])
    $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$Sid'"
    if (-not $profile -or $profile.Special) {
        throw "No regular local user profile exists for SID '$Sid'."
    }
}

function Set-StatusTask {
    param([Parameter(Mandatory)][string]$Sid)

    Assert-SelectableUser -Sid $Sid
    Initialize-TaskFolder
    $action = New-ScheduledTaskAction -Execute $installedTray
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Sid
    $principal = New-ScheduledTaskPrincipal -UserId $Sid -LogonType Interactive `
        -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName ($taskPrefix + $Sid) -TaskPath $taskPath `
        -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Force | Out-Null
}

function Get-InstalledTrayProcessUserSids {
    $sids = @{}
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process `
        -Filter "Name='xucRunTray.exe'")) {
        if (-not $process.ExecutablePath -or
            -not [string]::Equals($process.ExecutablePath, $installedTray,
                [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if ($owner.ReturnValue -eq 0 -and
            -not [string]::IsNullOrWhiteSpace($owner.Sid)) {
            $sids[$owner.Sid] = $true
        }
    }
    return @($sids.Keys)
}

function Test-TrayProcessForUser {
    param([Parameter(Mandatory)][string]$Sid)

    return $Sid -in @(Get-InstalledTrayProcessUserSids)
}

function Test-InteractiveUserLoggedOn {
    param([Parameter(Mandatory)][string]$Sid)

    foreach ($process in @(Get-CimInstance -ClassName Win32_Process `
        -Filter "Name='explorer.exe'")) {
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if ($owner.ReturnValue -eq 0 -and $owner.Sid -eq $Sid) {
            return $true
        }
    }
    return $false
}

function Start-StatusTaskIfUserLoggedOn {
    param([Parameter(Mandatory)][string]$Sid)

    if (-not (Test-InteractiveUserLoggedOn -Sid $Sid)) {
        return 'Deferred'
    }
    try {
        Start-ScheduledTask -TaskName ($taskPrefix + $Sid) -TaskPath $taskPath
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            if (Test-TrayProcessForUser -Sid $Sid) {
                return 'Started'
            }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        Write-Warning "xucRun Tray did not start for the logged-on SID '$Sid'."
    }
    catch {
        Write-Warning "xucRun Tray could not be started for SID '$Sid': $($_.Exception.Message)"
    }
    return 'Failed'
}

function Remove-StatusTasks {
    Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName.StartsWith($taskPrefix) } |
        Unregister-ScheduledTask -Confirm:$false
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    try {
        $folder = $scheduler.GetFolder('\').GetFolder('xucRun')
        if ($folder.GetTasks(0).Count -eq 0 -and
            $folder.GetFolders(0).Count -eq 0) {
            $scheduler.GetFolder('\').DeleteFolder('xucRun', 0)
        }
    }
    catch {
        if ($_.Exception.HResult -notin @(-2147024894, -2147024893)) {
            throw
        }
    }
}

function Set-InstallerLogDirectoryAcl {
    param([Parameter(Mandatory)][string]$Path)

    $inheritance =
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $administratorsSid =
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $usersSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($administratorsSid)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $systemSid, 'FullControl', $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $administratorsSid, 'FullControl', $inheritance, $propagation, $allow))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $usersSid, 'ReadAndExecute', $inheritance, $propagation, $allow))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Write-TrayUninstallDiagnostic {
    param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)

    New-Item -ItemType Directory -Path $installerLogDirectory -Force | Out-Null
    Set-InstallerLogDirectoryAcl -Path $installerLogDirectory
    $logPath = Join-Path $installerLogDirectory (
        'xucRunTray-Uninstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    $lines = @(
        "TimestampUtc=$([DateTimeOffset]::UtcNow.ToString('o'))",
        'Component=xucRun Tray uninstall',
        "Computer=$env:COMPUTERNAME",
        "PowerShell=$($PSVersionTable.PSVersion)",
        '',
        'ExceptionType:',
        $ErrorRecord.Exception.GetType().FullName,
        '',
        'Message:',
        $ErrorRecord.Exception.Message,
        '',
        'Category:',
        [string]$ErrorRecord.CategoryInfo,
        '',
        'FullyQualifiedErrorId:',
        $ErrorRecord.FullyQualifiedErrorId,
        '',
        'Position:',
        $ErrorRecord.InvocationInfo.PositionMessage,
        '',
        'ScriptStackTrace:',
        $ErrorRecord.ScriptStackTrace
    )
    Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
    return $logPath
}

function Show-TrayUninstallFailure {
    param(
        [Parameter(Mandatory)][string]$Details,
        [string]$LogPath,
        [string]$LogError
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $german =
        [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'de'
    if ($german) {
        $title = 'xucRun Tray deinstallieren'
        $headingText = 'Die Deinstallation ist fehlgeschlagen.'
        $detailsText = 'Fehlerdetails:'
        $logText = 'Diagnoseprotokoll:'
        $openText = 'Protokollordner ' + [char]0x00F6 + 'ffnen'
        $closeText = 'Schlie' + [char]0x00DF + 'en'
        $logUnavailable = 'Das Diagnoseprotokoll konnte nicht geschrieben werden.'
        $openFailed = 'Der Protokollordner konnte nicht ge' +
            [char]0x00F6 + 'ffnet werden.'
    }
    else {
        $title = 'Uninstall xucRun Tray'
        $headingText = 'Uninstall failed.'
        $detailsText = 'Error details:'
        $logText = 'Diagnostic log:'
        $openText = 'Open log folder'
        $closeText = 'Close'
        $logUnavailable = 'The diagnostic log could not be written.'
        $openFailed = 'The log folder could not be opened.'
    }

    $form = [Windows.Forms.Form]::new()
    $form.Text = $title
    $form.ClientSize = [Drawing.Size]::new(680, 330)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'

    $heading = [Windows.Forms.Label]::new()
    $heading.AutoSize = $true
    $heading.Font = [Drawing.Font]::new(
        $form.Font, [Drawing.FontStyle]::Bold)
    $heading.Location = [Drawing.Point]::new(20, 18)
    $heading.Text = $headingText
    $form.Controls.Add($heading)

    $detailsLabel = [Windows.Forms.Label]::new()
    $detailsLabel.SetBounds(20, 52, 640, 20)
    $detailsLabel.Text = $detailsText
    $form.Controls.Add($detailsLabel)
    $detailsBox = [Windows.Forms.TextBox]::new()
    $detailsBox.SetBounds(20, 74, 640, 86)
    $detailsBox.Multiline = $true
    $detailsBox.ReadOnly = $true
    $detailsBox.ScrollBars = 'Vertical'
    $detailsBox.Text = $Details
    $form.Controls.Add($detailsBox)

    $logLabel = [Windows.Forms.Label]::new()
    $logLabel.SetBounds(20, 176, 640, 20)
    $logLabel.Text = $logText
    $form.Controls.Add($logLabel)
    $logBox = [Windows.Forms.TextBox]::new()
    $logBox.SetBounds(20, 198, 640, 24)
    $logBox.ReadOnly = $true
    $logBox.Text = if ($LogPath) {
        $LogPath
    } else {
        "$logUnavailable $LogError".Trim()
    }
    $form.Controls.Add($logBox)

    $openButton = [Windows.Forms.Button]::new()
    $openButton.SetBounds(378, 274, 180, 34)
    $openButton.Text = $openText
    $openButton.Enabled = -not [string]::IsNullOrWhiteSpace($LogPath)
    $openButton.Add_Click({
        try {
            [void][Diagnostics.Process]::Start(
                'explorer.exe',
                ('"{0}"' -f [IO.Path]::GetDirectoryName($LogPath)))
        }
        catch {
            [Windows.Forms.MessageBox]::Show(
                "$openFailed`r`n`r`n$($_.Exception.Message)",
                $title, 'OK', 'Error') | Out-Null
        }
    })
    $form.Controls.Add($openButton)

    $closeButton = [Windows.Forms.Button]::new()
    $closeButton.SetBounds(566, 274, 94, 34)
    $closeButton.Text = $closeText
    $closeButton.DialogResult = 'OK'
    $form.AcceptButton = $closeButton
    $form.CancelButton = $closeButton
    $form.Controls.Add($closeButton)

    [void]$form.ShowDialog()
}

function Remove-Tray {
    Stop-InstalledTray
    Remove-StatusTasks
    foreach ($path in @(
        $installedTray,
        (Join-Path $languageDirectory $trayLanguageFiles[0]),
        (Join-Path $languageDirectory $trayLanguageFiles[1])
    )) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $uninstallPath -Recurse -Force `
        -ErrorAction SilentlyContinue
    Write-Host 'xucRun Tray was removed. The xucRun installation was not changed.'
    Remove-Item -LiteralPath $installedInstaller -Force -ErrorAction SilentlyContinue
}

function Show-TrayUninstallSuccess {
    $german =
        [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'de'
    if ($german) {
        $title = 'xucRun Tray deinstallieren'
        $message = @'
xucRun Tray wurde erfolgreich deinstalliert.

Entfernt wurden:
- Tray-Programmdateien und Sprachressourcen
- alle xucRun-Tray-Autostartaufgaben
- Deinstallationseintrag xucRun Tray

Beibehalten wurden:
- xucRun Core und der Brokerdienst
- das lokale xucRun-Zertifikat
- gespeicherte Anmeldedaten und Freigaben
'@
    }
    else {
        $title = 'Uninstall xucRun Tray'
        $message = @'
xucRun Tray was uninstalled successfully.

Removed:
- Tray program files and language resources
- all xucRun Tray autostart tasks
- xucRun Tray uninstall entry

Unchanged:
- xucRun Core and the broker service
- the local xucRun certificate
- stored credentials and approvals
'@
    }
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show(
        $message.Trim(), $title, 'OK', 'Information') | Out-Null
}

if ($Uninstall) {
    try {
        Assert-WindowsPowerShell
        Assert-Administrator
        Remove-Tray
        Show-TrayUninstallSuccess
    }
    catch {
        $uninstallError = $_
        $logPath = $null
        $logError = $null
        try {
            $logPath = Write-TrayUninstallDiagnostic -ErrorRecord $uninstallError
        }
        catch {
            $logError = $_.Exception.Message
        }
        Show-TrayUninstallFailure -Details $uninstallError.Exception.Message `
            -LogPath $logPath -LogError $logError
        throw
    }
    return
}

Assert-WindowsPowerShell
Assert-Administrator

$packageRoot = (Resolve-Path -LiteralPath $PackageDirectory).ProviderPath
$manifestPath = Join-Path $packageRoot 'TrayPackage.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Tray package manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.component -ne 'xucRun-Tray' -or
    $manifest.signingPolicy -ne 'same-as-installed-core') {
    throw 'The Tray package manifest is unsupported.'
}
if (-not (Test-Path -LiteralPath $installedCore -PathType Leaf)) {
    throw "xucRun is not installed at the supported path: $installedCore"
}
Assert-NotReparsePoint -Path $installDirectory
Assert-NotReparsePoint -Path $languageDirectory
if (-not (Test-Path -LiteralPath $coreParametersPath)) {
    throw 'The supported xucRun broker authorization is missing.'
}
if (Test-Path -LiteralPath $coreUninstallPath) {
    $registeredCoreLocation =
        (Get-Item -LiteralPath $coreUninstallPath).GetValue('InstallLocation', '')
    if (-not [string]::Equals(
        [IO.Path]::GetFullPath([string]$registeredCoreLocation),
        [IO.Path]::GetFullPath($installDirectory),
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The registered xucRun installation path is invalid.'
    }
}
if ((Test-Path -LiteralPath $installedTray -PathType Leaf) -and
    -not (Test-Path -LiteralPath $uninstallPath)) {
    throw 'A combined xucRun Distribution installation is present. ' +
        'Use its installer instead of the separate Tray add-on.'
}
$coreVersion = (Get-Item -LiteralPath $installedCore).VersionInfo.ProductVersion
if ($coreVersion -ne $manifest.requiredCoreProductVersion) {
    throw "Tray version $($manifest.productVersion) requires xucRun " +
        "$($manifest.requiredCoreProductVersion); installed version is $coreVersion."
}
$expectedSigner = Get-ValidSignerHash -Path $installedCore
$parameters = Get-Item -LiteralPath $coreParametersPath
$registeredClientPath = [string]$parameters.GetValue(
    'SensitiveClientImagePath', '')
$registeredSigner = $parameters.GetValue('SensitiveClientSignerSha256', $null)
if (-not [string]::Equals(
    [IO.Path]::GetFullPath($registeredClientPath),
    [IO.Path]::GetFullPath($installedCore),
    [StringComparison]::OrdinalIgnoreCase) -or
    $registeredSigner -isnot [byte[]] -or
    [Convert]::ToBase64String($registeredSigner) -ne $expectedSigner) {
    throw 'The installed xucRun broker authorization does not match xucRun.exe.'
}
$payload = @(
    @{ Relative = 'xucRunTray.exe'; Destination = $installedTray },
    @{
        Relative = 'Languages\xucRunTray.de-DE.dll'
        Destination = Join-Path $languageDirectory 'xucRunTray.de-DE.dll'
    },
    @{
        Relative = 'Languages\xucRunTray.en-US.dll'
        Destination = Join-Path $languageDirectory 'xucRunTray.en-US.dll'
    }
)
foreach ($file in $payload) {
    $source = Join-Path $packageRoot $file.Relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Tray package file is missing: $source"
    }
    $entry = @($manifest.files | Where-Object {
        $_.path -eq $file.Relative.Replace('\', '/')
    })
    if ($entry.Count -ne 1 -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
        $entry[0].sha256) {
        throw "Tray package hash validation failed: $($file.Relative)"
    }
    if ($file.Relative -eq 'xucRunTray.exe' -and
        (Get-Item -LiteralPath $source).VersionInfo.ProductVersion -ne
            $manifest.productVersion) {
        throw "Tray package version validation failed: $($file.Relative)"
    }
    if ((Get-ValidSignerHash -Path $source) -ne $expectedSigner) {
        throw "Tray package signer does not match the installed xucRun: $($file.Relative)"
    }
}
Assert-SelectableUser -Sid $UserSid
if ($ValidateOnly) {
    Write-Host "xucRun Tray package validation passed for xucRun $coreVersion and SID $UserSid."
    return
}

$staging = Join-Path $programFiles (
    '.xucRun-Tray-staging-' + [Guid]::NewGuid().ToString('N'))
$backup = Join-Path $programFiles (
    '.xucRun-Tray-backup-' + [Guid]::NewGuid().ToString('N'))
$startDisposition = 'Deferred'
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    foreach ($file in $payload) {
        $target = Join-Path $staging $file.Relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
            -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageRoot $file.Relative) `
            -Destination $target
        $manifestEntry = @($manifest.files | Where-Object {
            $_.path -eq $file.Relative.Replace('\', '/')
        })[0]
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne
            $manifestEntry.sha256 -or
            (Get-ValidSignerHash -Path $target) -ne $expectedSigner) {
            throw "Protected Tray staging validation failed: $($file.Relative)"
        }
    }
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Install-xucRunTray.ps1') `
        -Destination (Join-Path $staging 'Install-xucRunTray.ps1')

    $runningTrayUserSids = @(Get-InstalledTrayProcessUserSids)
    Stop-InstalledTray
    New-Item -ItemType Directory -Path $backup | Out-Null
    foreach ($file in $payload) {
        if (Test-Path -LiteralPath $file.Destination -PathType Leaf) {
            $backupPath = Join-Path $backup $file.Relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) `
                -Force | Out-Null
            Copy-Item -LiteralPath $file.Destination -Destination $backupPath
        }
    }
    if (Test-Path -LiteralPath $installedInstaller -PathType Leaf) {
        Copy-Item -LiteralPath $installedInstaller `
            -Destination (Join-Path $backup 'Install-xucRunTray.ps1')
    }

    try {
        New-Item -ItemType Directory -Path $languageDirectory -Force | Out-Null
        foreach ($file in $payload) {
            Copy-Item -LiteralPath (Join-Path $staging $file.Relative) `
                -Destination $file.Destination -Force
            if ((Get-ValidSignerHash -Path $file.Destination) -ne $expectedSigner) {
                throw "Installed Tray signature verification failed: $($file.Destination)"
            }
        }
        Copy-Item -LiteralPath (Join-Path $staging 'Install-xucRunTray.ps1') `
            -Destination $installedInstaller -Force
        Set-StatusTask -Sid $UserSid

        New-Item -Path $uninstallPath -Force | Out-Null
        Set-TrayUninstallRegistryAcl
        New-ItemProperty -Path $uninstallPath -Name DisplayName `
            -PropertyType String -Value 'xucRun Tray' -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name DisplayVersion `
            -PropertyType String -Value $manifest.productVersion -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name InstallDate `
            -PropertyType String -Value (Get-Date -Format 'yyyyMMdd') -Force |
            Out-Null
        New-ItemProperty -Path $uninstallPath -Name InstallTimestampUtc `
            -PropertyType String -Value (
                [DateTimeOffset]::UtcNow.ToString(
                    'o', [Globalization.CultureInfo]::InvariantCulture)) -Force |
            Out-Null
        New-ItemProperty -Path $uninstallPath -Name Publisher `
            -PropertyType String -Value 'HT64' -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name InstallLocation `
            -PropertyType String -Value $installDirectory -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name DisplayIcon `
            -PropertyType String -Value $installedTray -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name UninstallString `
            -PropertyType String -Value (
                'powershell.exe -NoProfile -WindowStyle Hidden ' +
                '-ExecutionPolicy Bypass -File "' +
                $installedInstaller + '" -Uninstall') -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name NoModify `
            -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $uninstallPath -Name NoRepair `
            -PropertyType DWord -Value 1 -Force | Out-Null
        foreach ($sid in @($runningTrayUserSids + $UserSid | Sort-Object -Unique)) {
            $disposition = Start-StatusTaskIfUserLoggedOn -Sid $sid
            if ($sid -eq $UserSid) {
                $startDisposition = $disposition
            }
        }
    }
    catch {
        foreach ($file in $payload) {
            $backupPath = Join-Path $backup $file.Relative
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Copy-Item -LiteralPath $backupPath `
                    -Destination $file.Destination -Force
            }
            else {
                Remove-Item -LiteralPath $file.Destination -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        $backupInstaller = Join-Path $backup 'Install-xucRunTray.ps1'
        if (Test-Path -LiteralPath $backupInstaller -PathType Leaf) {
            Copy-Item -LiteralPath $backupInstaller `
                -Destination $installedInstaller -Force
        }
        foreach ($sid in $runningTrayUserSids) {
            [void](Start-StatusTaskIfUserLoggedOn -Sid $sid)
        }
        throw
    }
}
finally {
    Remove-Item -LiteralPath $staging, $backup -Recurse -Force `
        -ErrorAction SilentlyContinue
}

Write-Host "xucRun Tray $($manifest.productVersion) installed for SID $UserSid."
Write-Host "XUCRUN_TRAY_START_DISPOSITION=$startDisposition"
