<#
.SYNOPSIS
Tests the standalone architecture and repository policy of xucRun Tray.

.DESCRIPTION
Scans the worktree for copied Core source trees and secret-bearing file
types, checks that build files contain only the supported sibling xucRun
references and explicit signing hook, validates required public files and
Dependencies.json, and verifies CI, packaging, installer-project, and
machine-installer contracts. It compares FILE_REGISTER.md with every tracked
and unignored file, validates structured file-head documentation according to
each format's comment syntax except for the two explicitly path-bound changelog
exceptions, and parses every repository script to require complete
comment-based help for all declared parameters.

.EXAMPLE
.\Test-TrayArchitecture.ps1

Runs the repository-boundary, dependency, safety, installer, file-register,
file-head, and script-help checks against the current worktree.

.NOTES
Requires PowerShell and Git, a Git worktree rooted at the script directory,
and the repository source files; built artifacts are not required. The test
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
    'runtime_info::Collect(maintenanceScript)',
    'runtime_info::Format(commonInfo)'
)) {
    if (-not $trayInfoSource.Contains($requiredInfoSourceContract)) {
        throw "Tray /info is missing source contract '$requiredInfoSourceContract'."
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
