<#
.SYNOPSIS
Tests the standalone architecture and repository policy of xucRun Tray.

.DESCRIPTION
Scans the worktree for copied Core source trees and secret-bearing file
types, checks that build files contain only the supported sibling xucRun
references and explicit signing hook, validates required public files and
Dependencies.json, and verifies CI, packaging, installer-project,
machine-installer, and signing-script contracts, including that the signing
script creates its staging directory together with the restricting access
control list and that the installer scripts do not locate directories through
environment variables. It tests the installer tabs, layout, language switching,
account selection, acknowledgment gate and its localized label semantics,
Apache license resources without
additional selling restrictions, and consistency of its license introduction,
security and status notices with both README languages. It compares FILE_REGISTER.md with every tracked
and unignored file, validates structured file-head documentation according to
each format's comment syntax except for the two explicitly path-bound changelog
exceptions, and parses every repository script to require complete
comment-based help for all declared parameters. It verifies that Tray /info
reuses the shared Core resource, including its Apache License 2.0 open-source
designation.

.EXAMPLE
.\Test-TrayArchitecture.ps1

Runs the repository-boundary, dependency, safety, installer, file-register,
file-head, and script-help checks against the current worktree.

.NOTES
Requires Windows PowerShell, Windows Forms, and Git, a Git worktree rooted at
the script directory, and the repository source files; built artifacts are not required. The test
is read-only and does not contact GitHub or modify the worktree. Script
discovery is limited to tracked and unignored .ps1, .bat, .cmd, and .py
files; PowerShell scripts are syntax-checked and documentation-checked.
CHANGELOG.md and CHANGELOG.de.md are the only commentable files exempt from
structured metadata heads. Normal completion returns 0 when run with
powershell.exe -File. Any boundary, dependency, policy, syntax, or
documentation violation causes a terminating error and a nonzero process exit
code.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot

$repositoryFileNames = @(
    & git -C $repositoryRoot ls-files --cached --others --exclude-standard
)
if ($LASTEXITCODE -ne 0) {
    throw 'Tracked and unignored repository files could not be enumerated with Git.'
}
if ($repositoryFileNames.Count -eq 0) {
    throw 'The repository does not contain any tracked or unignored files.'
}
$repositoryFileNames = @($repositoryFileNames | ForEach-Object {
    $_.Replace('\', '/')
})

$registerPath = Join-Path $repositoryRoot 'FILE_REGISTER.md'
if (-not (Test-Path -LiteralPath $registerPath -PathType Leaf)) {
    throw 'FILE_REGISTER.md is missing.'
}
$registerText = [IO.File]::ReadAllText($registerPath)
$registerMatches = [regex]::Matches(
    $registerText,
    '(?m)^\|\s*`(?<Path>[^`\r\n]+)`\s*\|\s*(?<Class>[^|\r\n]+?)\s*\|\s*(?<Purpose>[^|\r\n]+?)\s*\|\s*$')
if ($registerMatches.Count -eq 0) {
    throw 'FILE_REGISTER.md does not contain any valid file rows.'
}

$registeredNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($registerMatch in $registerMatches) {
    $registeredName = $registerMatch.Groups['Path'].Value
    if (-not $registeredNames.Add($registeredName)) {
        throw "FILE_REGISTER.md contains duplicate path '$registeredName'."
    }
    if ([string]::IsNullOrWhiteSpace($registerMatch.Groups['Class'].Value)) {
        throw "FILE_REGISTER.md has an empty class for '$registeredName'."
    }
    if ([string]::IsNullOrWhiteSpace($registerMatch.Groups['Purpose'].Value)) {
        throw "FILE_REGISTER.md has an empty purpose for '$registeredName'."
    }
}

$actualNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($repositoryFileName in $repositoryFileNames) {
    if (-not $actualNames.Add($repositoryFileName)) {
        throw "Git returned duplicate repository path '$repositoryFileName'."
    }
}
$missingRegisterNames = @($repositoryFileNames | Where-Object {
    -not $registeredNames.Contains($_)
})
$extraRegisterNames = @($registeredNames | Where-Object {
    -not $actualNames.Contains($_)
})
if ($missingRegisterNames.Count -ne 0 -or $extraRegisterNames.Count -ne 0) {
    throw ('FILE_REGISTER.md does not exactly cover tracked and unignored files. ' +
        "Missing: $($missingRegisterNames -join ', '); " +
        "Extra: $($extraRegisterNames -join ', ')")
}

$lineCommentExtensions = @('.cpp', '.h', '.rc', '.rcinc')
$hashCommentExtensions = @('.yml', '.yaml')
$hashCommentNames = @('.gitattributes', '.gitignore')
$xmlCommentExtensions = @('.props', '.targets', '.vcxproj')
$noCommentExtensions = @('.json', '.png', '.sln')
$noCommentNames = @('LICENSE', 'NOTICE')
$fileHeadExceptionNames = @('CHANGELOG.de.md', 'CHANGELOG.md')
foreach ($repositoryFileName in $repositoryFileNames) {
    $filePath = Join-Path $repositoryRoot $repositoryFileName
    $extension = [IO.Path]::GetExtension($repositoryFileName).ToLowerInvariant()
    $leafName = [IO.Path]::GetFileName($repositoryFileName)

    if ($repositoryFileName -in $fileHeadExceptionNames) {
        continue
    }
    if ($extension -eq '.ps1') {
        continue
    }
    if ($extension -in $noCommentExtensions -or $leafName -in $noCommentNames) {
        continue
    }

    $fileText = [IO.File]::ReadAllText($filePath)
    if ($extension -eq '.md') {
        $headPattern = '(?s)\A<!--\r?\nPurpose:\s*\S[^\r\n]*\r?\n' +
            'Approach:\s*\S[^\r\n]*\r?\n-->\r?\n'
    }
    elseif ($extension -in $lineCommentExtensions) {
        $headPattern = '\A// Purpose:\s*\S[^\r\n]*\r?\n' +
            '// Approach:\s*\S[^\r\n]*\r?\n'
    }
    elseif ($extension -in $hashCommentExtensions -or $leafName -in $hashCommentNames) {
        $headPattern = '\A# Purpose:\s*\S[^\r\n]*\r?\n' +
            '# Approach:\s*\S[^\r\n]*\r?\n'
    }
    elseif ($extension -in $xmlCommentExtensions) {
        $headPattern = '(?s)\A<\?xml[^>]*\?>\r?\n<!--\r?\n' +
            '\s*Purpose:\s*\S[^\r\n]*\r?\n' +
            '\s*Approach:\s*\S[^\r\n]*\r?\n-->\r?\n'
    }
    elseif ($repositoryFileName -eq '.githooks/pre-push') {
        $headPattern = '\A#!/bin/sh\r?\n# Purpose:\s*\S[^\r\n]*\r?\n' +
            '# Approach:\s*\S[^\r\n]*\r?\n'
    }
    else {
        throw "Repository file '$repositoryFileName' has no explicit file-head documentation policy."
    }

    if ($fileText -notmatch $headPattern) {
        throw "Repository file '$repositoryFileName' has no integrated Purpose and Approach in its file head."
    }
}

$trackedScriptNames = @(
    $repositoryFileNames | Where-Object {
        [IO.Path]::GetExtension($_).ToLowerInvariant() -in
            @('.ps1', '.bat', '.cmd', '.py')
    }
)
if ($trackedScriptNames.Count -eq 0) {
    throw 'The repository does not contain any tracked or unignored scripts.'
}
foreach ($scriptName in $trackedScriptNames) {
    $scriptPath = Join-Path $repositoryRoot $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Tracked script is missing from the worktree: $scriptName"
    }
    if ([IO.Path]::GetExtension($scriptPath) -ne '.ps1') {
        throw "Tracked script '$scriptName' does not have a documentation validator."
    }

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell parser error in '$scriptName': $($errors.Message -join '; ')"
    }
    $helpToken = @($tokens | Where-Object {
        $_.Kind -eq [Management.Automation.Language.TokenKind]::Comment -and
        $_.Text.StartsWith('<#') -and
        $_.Extent.StartOffset -lt $ast.ParamBlock.Extent.StartOffset
    }) | Select-Object -First 1
    if (-not $helpToken) {
        throw "Script '$scriptName' has no comment-based help in its file header."
    }
    foreach ($section in @('SYNOPSIS', 'DESCRIPTION', 'EXAMPLE', 'NOTES')) {
        if ($helpToken.Text -notmatch
            "(?ms)^\s*\.$section\s*\r?\n\s*\S.+?(?=^\s*\.[A-Z]+|\s*#>\s*$)") {
            throw "Script '$scriptName' has no complete .$section help section."
        }
    }
    [void]($helpToken.Text -match
        '(?ms)^\s*\.SYNOPSIS\s*\r?\n(?<Synopsis>.+?)(?=^\s*\.[A-Z]+)')
    $recognizedHelp = Get-Help -Name $scriptPath -Full -ErrorAction Stop
    if ([string]$recognizedHelp.Synopsis -ne $matches.Synopsis.Trim()) {
        throw "PowerShell does not recognize the comment-based help in '$scriptName'."
    }
    foreach ($parameter in @($ast.ParamBlock.Parameters)) {
        $parameterName = $parameter.Name.VariablePath.UserPath
        if ($helpToken.Text -notmatch
            "(?m)^\s*\.PARAMETER\s+$([regex]::Escape($parameterName))\s*$") {
            throw "Script '$scriptName' has no .PARAMETER help for '$parameterName'."
        }
    }
}

$forbiddenDirectories = @(
    'xucRun',
    'xucRunApproval',
    'xucRunBroker',
    'xucRunClientCommon',
    'xucRunCore',
    'xucRunInstaller',
    'xucRunLanguageDeDe',
    'xucRunLanguageEnUs',
    'xucRunSharedResources'
)
foreach ($directory in $forbiddenDirectories) {
    $candidate = Join-Path $repositoryRoot $directory
    $copiedSources = @(
        Get-ChildItem -LiteralPath $candidate -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\x64\\' }
    )
    if ($copiedSources.Count -ne 0) {
        throw "Standalone Tray repository contains copied xucRun sources below '$directory'."
    }
}

$project = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\xucRunTray.vcxproj'))
foreach ($requiredReference in @(
    '$(XucRunCoreRoot)\xucRunCore\xucRunCore.vcxproj',
    '$(XucRunCoreRoot)\xucRunClientCommon\xucRunClientCommon.vcxproj',
    '$(XucRunCoreRoot)\xucRunSharedResources\ClientResources.rc'
)) {
    if (-not $project.Contains($requiredReference)) {
        throw "Tray project is missing sibling xucRun reference '$requiredReference'."
    }
}
if ($project -match '\.\.\\xucRun(Core|ClientCommon|SharedResources)') {
    throw 'Tray project still contains a legacy in-repository xucRun path.'
}

$trackedCandidates = @(
    Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Force |
        Where-Object {
            $_.FullName -notlike (Join-Path $repositoryRoot '.git\*') -and
            $_.FullName -notlike (Join-Path $repositoryRoot 'artifacts\*') -and
            $_.FullName -notmatch '\\x64\\'
        }
)
foreach ($file in $trackedCandidates) {
    if ($file.Extension -in @('.pfx', '.p12', '.pvk', '.key', '.pem', '.env')) {
        throw "Tray repository contains forbidden secret-bearing file '$($file.FullName)'."
    }
}

$buildProperties = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Directory.Build.props'))
$buildTargets = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Directory.Build.targets'))
$privateRootProperty = 'XucRun' + 'DistributionRoot'
$privateRepositoryName = 'xucRun-' + 'Distribution'
if (($buildProperties + $buildTargets).Contains($privateRootProperty) -or
    ($buildProperties + $buildTargets).Contains($privateRepositoryName)) {
    throw 'Public Tray build files must not reference the private deployment repository.'
}
if (-not $buildTargets.Contains('$(XucRunSignScript)')) {
    throw 'Public Tray signing must use the explicitly supplied XucRunSignScript.'
}
foreach ($publicFile in @(
    'Dependencies.json',
    'FILE_REGISTER.md',
    'LICENSE',
    'NOTICE',
    'README.md',
    'README.de.md',
    'SECURITY.md',
    'SECURITY.de.md',
    'CONTRIBUTING.md',
    'CONTRIBUTING.de.md',
    'Test-PublicRepository.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $publicFile) -PathType Leaf)) {
        throw "Public Tray repository file is missing: $publicFile"
    }
}
$dependencies = Get-Content -LiteralPath `
    (Join-Path $repositoryRoot 'Dependencies.json') -Raw |
    ConvertFrom-Json
if ($dependencies.schemaVersion -ne 1 -or
    $dependencies.core.repository -ne 'HT64/xucRun' -or
    $dependencies.core.commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Dependencies.json does not contain a valid xucRun dependency.'
}
$workflow = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot '.github\workflows\ci.yml'))
foreach ($requiredContract in @(
    'Dependencies.json',
    'steps.core_dependency.outputs.repository',
    'steps.core_dependency.outputs.commit'
)) {
    if (-not $workflow.Contains($requiredContract)) {
        throw "Tray CI is missing dependency contract '$requiredContract'."
    }
}
$packageScript = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'New-xucRunTray-Package.ps1'))
foreach ($requiredContract in @(
    'Dependencies.json',
    '$dependencies.core.commit',
    '$coreCommit -ne $dependencies.core.commit'
)) {
    if (-not $packageScript.Contains($requiredContract)) {
        throw "Tray package creation is missing dependency contract '$requiredContract'."
    }
}

$forbiddenPublicTerms = @(
    ('Install-xucRun' + '-Icon.ps1'),
    ('combined ' + 'Distribution'),
    ('kombinierte ' + 'Distribution'),
    $privateRepositoryName
)
$publicTextFiles = @($repositoryFileNames | Where-Object {
    [IO.Path]::GetExtension($_).ToLowerInvariant() -in
        @('.cpp', '.h', '.md', '.ps1', '.rc', '.rcinc')
})
foreach ($relativePath in $publicTextFiles) {
    $text = [IO.File]::ReadAllText((Join-Path $repositoryRoot $relativePath))
    foreach ($forbiddenPublicTerm in $forbiddenPublicTerms) {
        if ($text.Contains($forbiddenPublicTerm)) {
            throw "Public Tray file '$relativePath' exposes private term '$forbiddenPublicTerm'."
        }
    }
}
$coreRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '..\xucRun-Core'))
$coreTextFiles = Get-ChildItem -LiteralPath $coreRoot -Recurse -File |
    Where-Object {
        $_.FullName -notlike (Join-Path $coreRoot '.git\*') -and
        $_.FullName -notlike (Join-Path $coreRoot 'artifacts\*') -and
        $_.FullName -notmatch '\\x64\\' -and
        $_.Extension.ToLowerInvariant() -in
            @('.cpp', '.h', '.md', '.ps1', '.rc', '.rcinc')
    }
foreach ($coreTextFile in $coreTextFiles) {
    $text = [IO.File]::ReadAllText($coreTextFile.FullName)
    foreach ($forbiddenPublicTerm in $forbiddenPublicTerms) {
        if ($text.Contains($forbiddenPublicTerm)) {
            throw "Public Core file '$($coreTextFile.FullName)' exposes private term '$forbiddenPublicTerm'."
        }
    }
}

$installerProject = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\xucRunTrayInstaller.vcxproj'))
foreach ($requiredContract in @(
    'New-xucRunTray-Package.ps1',
    'SignReleaseInstaller',
    'SignTrayArtifacts',
    'SignPayloadScript',
    'SignScriptPath'
)) {
    if (-not $installerProject.Contains($requiredContract)) {
        throw "Tray installer project is missing contract '$requiredContract'."
    }
}
$machineInstaller = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Install-xucRunTray.ps1'))
foreach ($requiredContract in @(
    'same-as-installed-core',
    'requiredCoreProductVersion',
    'Register-ScheduledTask',
    'EnableAutostart',
    'DisableAutostart',
    'Remove-StatusTask',
    'Set-TrayUninstallRegistryAcl',
    'RegistrySecurity',
    "Relative = 'Install-xucRunTray.ps1'",
    'Get-FileHash -LiteralPath $file.Destination',
    'xucRun Tray'
)) {
    if (-not $machineInstaller.Contains($requiredContract)) {
        throw "Tray machine installer is missing contract '$requiredContract'."
    }
}

$signingScript = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'Sign-xucRunTrayPackage.ps1'))
foreach ($requiredContract in @(
    'CommonApplicationData',
    '[void][IO.Directory]::CreateDirectory($path, $acl)',
    'Assert-ProtectedDirectory -Path $path',
    'Staged Tray payload file does not match its source'
)) {
    if (-not $signingScript.Contains($requiredContract)) {
        throw "Tray signing script is missing staging contract '$requiredContract'."
    }
}
foreach ($forbiddenContract in @(
    'New-Item -ItemType Directory -Path $path',
    'Set-Acl -LiteralPath $path',
    '$env:ProgramData',
    'GetTempPath'
)) {
    if ($signingScript.Contains($forbiddenContract)) {
        throw "Tray signing script stages without creation-time protection: " +
            "'$forbiddenContract'."
    }
}

foreach ($installerScript in @(
    'Install-xucRunTray.ps1',
    'xucRunTrayInstaller\Installer-Gui.ps1'
)) {
    $installerSource = [IO.File]::ReadAllText(
        (Join-Path $repositoryRoot $installerScript))
    foreach ($variable in @('$env:SystemRoot', '$env:ProgramFiles', '$env:ProgramData')) {
        if ($installerSource.Contains($variable)) {
            throw "$installerScript locates a path through the environment: $variable"
        }
    }
    if ($installerSource.Contains(
        'New-Item -ItemType Directory -Path $installerLogDirectory')) {
        throw "$installerScript creates its log directory before restricting it."
    }
}

$guiPath = Join-Path $repositoryRoot 'xucRunTrayInstaller\Installer-Gui.ps1'
$tokens = $null
$errors = $null
$guiSource = [IO.File]::ReadAllText($guiPath)
$guiAst = [Management.Automation.Language.Parser]::ParseInput(
    $guiSource, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Tray installer GUI parser error: $($errors.Message -join '; ')"
}
$languageInitialization =
    $guiSource.IndexOf('$script:language = Get-InitialInstallerLanguage')
$translationInitialization =
    $guiSource.IndexOf('$script:t = $texts[$script:language]')
if ($languageInitialization -lt 0 -or
    $translationInitialization -le $languageInitialization) {
    throw 'Tray installer translations are initialized before the startup language.'
}
foreach ($contract in @(
    '$acknowledgment.Checked = $false',
    '$acknowledgment.Add_CheckedChanged({ Update-InstallAvailability })',
    '$script:installInProgress = $true',
    '$tabs.TabPages.AddRange(@($settingsTab, $detailsTab, $securityTab, $licenseTab))',
    '$settingsTab.Controls.Add($languageCombo)',
    '$settingsTab.Controls.Add($userBox)',
    '$detailsTab.Controls.Add($details)',
    '$securityTab.Controls.Add($securityDetails)',
    '$licenseTab.Controls.Add($licenseIntroduction)',
    '$licenseTab.Controls.Add($licenseDetails)',
    '$readmeLink.Add_LinkClicked({',
    '$userBox.Enabled = $false',
    '$userBox.Enabled = $true'
)) {
    if (-not $guiSource.Contains($contract)) {
        throw "Tray license and security acknowledgment contract is missing: $contract"
    }
}
$textsAssignment = $guiAst.Find({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left.Extent.Text -eq '$texts'
}, $true)
if (-not $textsAssignment) {
    throw 'Tray installer translations were not found.'
}
. ([scriptblock]::Create($textsAssignment.Extent.Text))
$expectedAcknowledgments = @{
    de = 'Ich stimme den Lizenzbedingungen zu und habe die Sicherheitshinweise verstanden.'
    en = 'I agree to the license terms and understand the security information.'
}
foreach ($language in @('de', 'en')) {
    if ($texts[$language].Acknowledgment -cne $expectedAcknowledgments[$language]) {
        throw "Tray $language acknowledgment label is incorrect."
    }
}
foreach ($language in @('de', 'en')) {
    $readmeName = if ($language -eq 'de') { 'README.de.md' } else { 'README.md' }
    $heading = if ($language -eq 'de') {
        'Wichtige Sicherheitshinweise'
    } else {
        'Important security notices'
    }
    $completenessPattern = if ($language -eq 'de') {
        'Diese Sicherheitshinweise erheben keinen Anspruch auf Vollst\u00e4ndigkeit; nicht alle Risiken und Sicherheitsl\u00fccken k\u00f6nnen vorausgesehen oder ausgeschlossen werden\.'
    } else {
        'These security notices are not exhaustive; not all risks and security vulnerabilities can be anticipated or ruled out\.'
    }
    if ($texts[$language].SecurityNotice -notmatch $completenessPattern) {
        throw "Tray installer completeness notice is missing for '$language'."
    }
    $statusPattern = if ($language -eq 'de') {
        'Die Dokumentation beschreibt das vorgesehene Verhalten\. Der aktuelle Stand kann Fehler enthalten, davon abweichen und sich \u00e4ndern\.'
    } else {
        'The documentation describes the intended behavior\. The current state may contain defects, differ from that behavior, and change\.'
    }
    if ($texts[$language].StatusNotice -notmatch $statusPattern) {
        throw "Tray installer documentation status notice is missing for '$language'."
    }
    $sharedNoticePatterns = if ($language -eq 'de') {
        @(
            'Die Offenlegung allein ist jedoch weder eine Sicherheitsgarantie noch der Nachweis einer unabh\u00e4ngigen Sicherheitspr\u00fcfung\.',
            'Der Einsatz erfolgt eigenverantwortlich\. xucRun Tray sollte nur auf vertrauensw\u00fcrdigen, selbst verwalteten Systemen ohne erh\u00f6hten Schutzbedarf eingesetzt werden\.',
            'Soweit gesetzlich zul\u00e4ssig, \u00fcbernehmen der Autor und die Mitwirkenden keine Haftung f\u00fcr Sch\u00e4den, Datenverluste oder sonstige Folgen'
        )
    } else {
        @(
            'Disclosure alone is neither a security guarantee nor evidence of an independent security audit\.',
            'Use xucRun Tray at your own responsibility\. xucRun Tray should be used only on trusted, self-managed systems that do not require an elevated level of protection\.',
            'To the extent permitted by law, the author and contributors accept no liability for damage, data loss, or other consequences'
        )
    }
    foreach ($pattern in $sharedNoticePatterns) {
        if ($texts[$language].SecurityNotice -notmatch $pattern) {
            throw "Tray installer shared security notice is missing for '$language': $pattern"
        }
    }
    $readme = [IO.File]::ReadAllText((Join-Path $repositoryRoot $readmeName))
    $licenseHeading = if ($language -eq 'de') { 'Lizenz' } else { 'License' }
    $licenseSection = [regex]::Match($readme,
        '(?ms)^## ' + $licenseHeading + '\s*\r?\n(?<body>.*?)(?=^## |\z)')
    if (-not $licenseSection.Success -or
        $texts[$language].LicenseIntroduction -notmatch 'Apache License 2\.0' -or
        $licenseSection.Groups['body'].Value -notmatch 'Apache License 2\.0') {
        throw "Tray installer license introduction differs from $readmeName."
    }
    foreach ($entry in @(
        @{ Heading = $heading; Text = $texts[$language].SecurityNotice; Exact = $true },
        @{ Heading = 'Status'; Text = $texts[$language].StatusNotice; Exact = $false }
    )) {
        $pattern = '(?ms)^> \*\*' + [regex]::Escape($entry.Heading) +
            ':\*\* (?<body>.*?)(?:\r?\n\r?\n|\z)'
        $match = [regex]::Match($readme, $pattern)
        if (-not $match.Success) {
            throw "$readmeName is missing the $($entry.Heading) block."
        }
        $expected = $match.Groups['body'].Value -replace '(?m)^> ?', '' `
            -replace '\[([^\]]+)\]\([^)]+\)', '$1' -replace '\s+', ' '
        $actual = $entry.Text -replace '\s+', ' '
        $expected = $expected.Trim()
        $actual = $actual.Trim()
        if (($entry.Exact -and $expected -cne $actual) -or
            (-not $entry.Exact -and -not $expected.StartsWith($actual))) {
            throw "Tray installer $($entry.Heading) text differs from $readmeName."
        }
    }
    if ($texts[$language].ReadmeUrl -cne
        "https://github.com/HT64/xucRun-Tray/blob/main/$readmeName") {
        throw "Tray installer documentation link is incorrect for '$language'."
    }
}
$resources = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\Installer.rc'))
$installerMain = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayInstaller\main.cpp'))
foreach ($entry in @(
    @{ Resource = 'IDR_LICENSE RCDATA "..\\artifacts\\Payload\\Release\\LICENSE"'; Payload = '{ IDR_LICENSE, L"LICENSE", false }' },
    @{ Resource = 'IDR_NOTICE RCDATA "..\\artifacts\\Payload\\Release\\NOTICE"'; Payload = '{ IDR_NOTICE, L"NOTICE", false }' },
    @{ Resource = 'IDR_LICENSE RCDATA "..\\artifacts\\Payload\\Debug\\LICENSE"'; Payload = '{ IDR_LICENSE, L"LICENSE", false }' },
    @{ Resource = 'IDR_NOTICE RCDATA "..\\artifacts\\Payload\\Debug\\NOTICE"'; Payload = '{ IDR_NOTICE, L"NOTICE", false }' }
)) {
    if (-not $resources.Contains($entry.Resource) -or
        -not $installerMain.Contains($entry.Payload)) {
        throw "Tray installer must embed and extract $($entry.Resource)."
    }
}
$licenseText = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'LICENSE'))
$noticeText = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'NOTICE'))
if ($licenseText -notmatch '^\s*Apache License\r?\n\s*Version 2\.0, January 2004' -or
    $licenseText -match '(?i)commons[\s-]+clause' -or
    $noticeText -match '(?i)commons[\s-]+clause') {
    throw 'The Tray license and notice must use Apache 2.0 without Commons Clause.'
}
$availabilityFunction = $guiAst.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Update-InstallAvailability'
}, $true)
if (-not $availabilityFunction) {
    throw 'Tray installer Update-InstallAvailability was not found.'
}
. ([scriptblock]::Create($availabilityFunction.Extent.Text))
$acknowledgment = [pscustomobject]@{ Checked = $false }
$installButton = [pscustomobject]@{ Enabled = $true }
$script:installInProgress = $false
Update-InstallAvailability
if ($installButton.Enabled) {
    throw 'Tray installation must be disabled before acknowledgment.'
}
$acknowledgment.Checked = $true
Update-InstallAvailability
if (-not $installButton.Enabled) {
    throw 'Tray installation must be enabled after acknowledgment.'
}
$script:installInProgress = $true
Update-InstallAvailability
if ($installButton.Enabled) {
    throw 'Tray installation must remain disabled while an installation is in progress.'
}
$script:installInProgress = $false
$acknowledgment.Checked = $false
Update-InstallAvailability
if ($installButton.Enabled) {
    throw 'Withdrawing acknowledgment must disable Tray installation.'
}

& {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    foreach ($name in @(
        'Get-SelectedCulture', 'Get-CertificateArguments', 'Get-InstalledTrayText'
    )) {
        $definition = $guiAst.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $name
        }, $true)
        if (-not $definition) {
            throw "Tray installer GUI function is missing: $name"
        }
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    $script:language = 'de'
    $script:installInProgress = $false
    $manifest = [pscustomobject]@{ productVersion = '0.9.1.6' }
    $coreState = [pscustomobject]@{
        Version = '0.9.1.6'
        Signer = [pscustomobject]@{
            NotBefore = [datetime]'2025-01-01'
            NotAfter = [datetime]'2030-01-01'
            Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'
        }
    }
    $certificateName = 'Test certificate with a sufficiently long name to wrap in the installer'
    $installedTrayState = [pscustomobject]@{
        Version = '0.9.1.6'
        InstalledAt = [datetime]'2025-01-01'
    }
    $users = @(
        [pscustomobject]@{ Sid = 'S-1-5-21-1'; DisplayName = 'First user' },
        [pscustomobject]@{ Sid = 'S-1-5-21-2'; DisplayName = 'Session user' }
    )
    function Get-CurrentSessionUserSid { return 'S-1-5-21-2' }

    $start = $guiSource.IndexOf('$form = [Windows.Forms.Form]::new()')
    $end = $guiSource.IndexOf('$script:exitCode = 1602', $start)
    if ($start -lt 0 -or $end -lt 0) {
        throw 'Tray installer GUI construction could not be located.'
    }
    . ([scriptblock]::Create($guiSource.Substring($start, $end - $start)))
    try {
        $null = $form.Handle
        $null = $tabs.Handle
        $null = $settingsTab.Handle
        $null = $securityTab.Handle
        $null = $licenseTab.Handle
        if ($tabs.TabPages.Count -ne 4 -or
            $tabs.TabPages[0] -ne $settingsTab -or
            $tabs.TabPages[1] -ne $detailsTab -or
            $tabs.TabPages[2] -ne $securityTab -or
            $tabs.TabPages[3] -ne $licenseTab) {
            throw 'Tray installer tabs are not in the expected order.'
        }
        if ($userBox.SelectedItem.Sid -ne 'S-1-5-21-2') {
            throw 'Tray installer did not select the current session user.'
        }
        if ($acknowledgment.Checked -or $installButton.Enabled) {
            throw 'Tray installation must initially require acknowledgment.'
        }
        $expectedLicense = (($licenseText + "`n`nNOTICE`n`n" + $noticeText) `
            -replace "`r?`n", "`r`n")
        if ($licenseDetails.Text -cne $expectedLicense) {
            throw 'Tray installer does not display the complete license and notice.'
        }
        $acknowledgment.Checked = $true
        foreach ($index in @(0, 1)) {
            $languageCombo.SelectedIndex = $index
            $language = if ($index -eq 0) { 'de' } else { 'en' }
            if ($settingsTab.Text -cne $texts[$language].SettingsTab -or
                $detailsTab.Text -cne $texts[$language].DetailsTab -or
                $securityTab.Text -cne $texts[$language].SecurityTab -or
                $licenseTab.Text -cne $texts[$language].LicenseTab -or
                $licenseIntroduction.Text -cne $texts[$language].LicenseIntroduction -or
                $readmeLink.Text -cne $texts[$language].ReadmeLink -or
                -not $securityDetails.Text.Contains($texts[$language].SecurityNotice.Trim())) {
                throw "Tray installer tab translations are incorrect for $language."
            }
            if ($userBox.SelectedItem.Sid -ne 'S-1-5-21-2' -or
                -not $acknowledgment.Checked -or -not $installButton.Enabled) {
                throw "Changing to $language lost the selected user or acknowledgment."
            }
            foreach ($control in @($languageLabel, $languageCombo, $userLabel,
                $userBox, $version, $coreVersion, $certificateGroup, $installedTray)) {
                if ($control.Parent -ne $settingsTab -or
                    $control.Bottom -gt $settingsTab.ClientSize.Height -or
                    $control.Right -gt $settingsTab.ClientSize.Width) {
                    throw "Tray installer settings control '$($control.Text)' " +
                        "($($control.Bounds)) is outside its tab " +
                        "($($settingsTab.ClientSize)) in $language."
                }
            }
            if ($certificateGroup.Bottom -gt $installedTray.Top -or
                $coreCertificate.Bottom -gt $certificateGroup.ClientSize.Height -or
                $tabs.Bottom -gt $acknowledgment.Top -or
                $readmeLink.Bottom -gt $securityTab.ClientSize.Height -or
                $licenseIntroduction.Parent -ne $licenseTab -or
                $licenseIntroduction.Bottom -ge $licenseDetails.Top -or
                $licenseDetails.Bottom -gt $licenseTab.ClientSize.Height -or
                $licenseDetails.Height -lt 100) {
                throw "Tray installer controls overlap or are clipped in $language."
            }
        }
        $script:installInProgress = $true
        Update-InstallAvailability
        if ($installButton.Enabled) {
            throw 'Tray installation must be disabled while work is in progress.'
        }
    }
    finally {
        $form.Dispose()
        $script:installInProgress = $false
    }
}

$coreInfoResourcesPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot `
    '..\xucRun-Core\xucRunSharedResources\ClientResources.rc'))
if (-not (Test-Path -LiteralPath $coreInfoResourcesPath -PathType Leaf)) {
    throw "Pinned Core information resources are missing: $coreInfoResourcesPath"
}
$coreInfoResources = [IO.File]::ReadAllText($coreInfoResourcesPath)
$trayInfoResources = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTrayResources\TrayStringsDeDe.rcinc')) +
    [IO.File]::ReadAllText(
        (Join-Path $repositoryRoot 'xucRunTrayResources\TrayStringsEnUs.rcinc'))
foreach ($sharedInfoContract in @(
    'Program\nVersion:',
    'Programm\nVersion:',
    'Copyright:',
    'License: Apache License 2.0 (open source)',
    'Lizenz: Apache License 2.0 (Open Source)',
    'Architecture:',
    'Architektur:',
    'Signing certificate\n',
    'Signierzertifikat\n',
    'Current account\n',
    'Aktuelles Konto\n',
    'Elevation:',
    ('Rechteerh' + [char]0x00F6 + 'hung:')
)) {
    if (-not $coreInfoResources.Contains($sharedInfoContract)) {
        throw "Shared Core and Tray /info resources are missing '$sharedInfoContract'."
    }
    if ($trayInfoResources.Contains($sharedInfoContract)) {
        throw "Tray-specific /info resources duplicate shared contract '$sharedInfoContract'."
    }
}
$trayInfoSource = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\TrayCommandViews.cpp'))
foreach ($requiredInfoSourceContract in @(
    'ClientRuntimeInfo.h',
    'ClientUiCommon.h',
    'runtime_info::Collect(maintenanceScript)',
    'runtime_info::Format(commonInfo)',
    'GetProductComputerContextWindowTitle',
    'localization::TextId::InfoTitle'
)) {
    if (-not $trayInfoSource.Contains($requiredInfoSourceContract)) {
        throw "Tray /info is missing source contract '$requiredInfoSourceContract'."
    }
}
$trayMainSource = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\TrayMain.cpp'))
foreach ($requiredNameMappingContract in @(
    'DocumentationNameMapping.h',
    'documentation_names::Initialize(documentationNameError)'
)) {
    if (-not $trayMainSource.Contains($requiredNameMappingContract)) {
        throw "Tray startup is missing documentation-name mapping contract '$requiredNameMappingContract'."
    }
}
foreach ($requiredAutostartLabel in @(
    ('Windows-Anmeldeaufgabe ohne erh' + [char]0x00F6 + 'hte Rechte'),
    'Windows logon task without elevated privileges'
)) {
    if (-not $trayInfoResources.Contains($requiredAutostartLabel)) {
        throw "Tray /info is missing autostart label '$requiredAutostartLabel'."
    }
}
$trayMenuSource = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\ClientStatusMenu.cpp'))
foreach ($requiredHelpMenuContract in @(
    'HMENU helpMenu = CreatePopupMenu()',
    'ShowCoreHelpCommand',
    'ShowTrayHelpCommand',
    'MenuShowCoreHelp',
    'MenuShowTrayHelp'
)) {
    if (-not $trayMenuSource.Contains($requiredHelpMenuContract)) {
        throw "Tray menu is missing help submenu contract '$requiredHelpMenuContract'."
    }
}
foreach ($requiredLogMenuContract in @(
    'ShowBrokerEventsCommand',
    'MenuShowBrokerEvents',
    'const bool logFileQuerySucceeded =',
    'localization::TrayTextId::MenuDeleteAllLogFiles,',
    '? std::to_wstring(logFiles.size()) : unavailable'
)) {
    if (-not $trayMenuSource.Contains($requiredLogMenuContract)) {
        throw "Tray menu is missing event-log contract '$requiredLogMenuContract'."
    }
}
foreach ($requiredLogFileCountLabel in @(
    ('Alle Logdateien l' + [char]0x00F6 + 'schen... ({0})'),
    'Delete all log files... ({0})'
)) {
    if (-not $trayInfoResources.Contains($requiredLogFileCountLabel)) {
        throw "Tray resources are missing log-file count label '$requiredLogFileCountLabel'."
    }
}
foreach ($requiredEventLogLabel in @(
    'xucRun-Brokerereignisse anzeigen',
    'Show xucRun Broker events'
)) {
    if (-not $trayInfoResources.Contains($requiredEventLogLabel)) {
        throw "Tray resources are missing event-log label '$requiredEventLogLabel'."
    }
}
$trayActionSource = [IO.File]::ReadAllText(
    (Join-Path $repositoryRoot 'xucRunTray\ClientStatusActions.cpp'))
foreach ($requiredTrayHelpContract in @(
    'case Action::ShowTrayHelp:',
    'tray_commands::ShowHelp(owner)'
)) {
    if (-not $trayActionSource.Contains($requiredTrayHelpContract)) {
        throw "Tray menu is missing direct Tray help contract '$requiredTrayHelpContract'."
    }
}
foreach ($requiredEventLogContract in @(
    'ShowBrokerEvents(HWND owner)',
    'GetSystemDirectoryW(',
    'L"\\eventvwr.exe"',
    '/c:Application /f:',
    "Provider[@Name='xucRunBroker']",
    'executeInfo.lpVerb = L"open"',
    'BrokerEventsOpenFailed'
)) {
    if (-not $trayActionSource.Contains($requiredEventLogContract)) {
        throw "Tray event-log action is missing contract '$requiredEventLogContract'."
    }
}
$coreInfoSource = [IO.File]::ReadAllText([IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot '..\xucRun-Core\xucRun\ClientInfoCommand.cpp')))
foreach ($requiredInfoSourceContract in @(
    'ClientRuntimeInfo.h',
    'runtime_info::Collect()',
    'runtime_info::Format(commonInfo)'
)) {
    if (-not $coreInfoSource.Contains($requiredInfoSourceContract)) {
        throw "Core /info is missing source contract '$requiredInfoSourceContract'."
    }
}
$sharedInfoSource = [IO.File]::ReadAllText([IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot `
        '..\xucRun-Core\xucRunClientCommon\ClientRuntimeInfo.cpp')))
foreach ($requiredSharedInfoContract in @(
    'LegalCopyright',
    'VerifyWithSignerCertificate',
    'GetSignerCertificateInfo',
    'GetElevation()',
    'L"x64"',
    'GetLoadedLanguageResourcePath()',
    'GetCurrentUserSID',
    'ClientLogDirectory',
    'Install-xucRun.ps1',
    'maintenanceScriptPath'
)) {
    if (-not $sharedInfoSource.Contains($requiredSharedInfoContract)) {
        throw "Shared client /info is missing source contract '$requiredSharedInfoContract'."
    }
}

Write-Host 'xucRun standalone Tray architecture passed'
