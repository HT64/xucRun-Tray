# Purpose: Fails unless this worktree targets the private xucRun Tray repository.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,
    [string]$PushRemoteName,
    [string]$PushRemoteUrl
)

$ErrorActionPreference = 'Stop'
$expectedRepository = 'HT64/xucRun-Tray'

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Description
    )

    $output = & $Executable @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode.`n$text"
    }
    return $text.Trim()
}

function ConvertTo-GitHubRepositoryName {
    param([Parameter(Mandatory)][string]$Url)

    $value = $Url.Trim()
    foreach ($prefix in @(
        'https://github.com/',
        'ssh://git@github.com/',
        'git@github.com:'
    )) {
        if ($value.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $value = $value.Substring($prefix.Length).TrimEnd('/')
            if ($value.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
                $value = $value.Substring(0, $value.Length - 4)
            }
            if ($value -match '^[^/]+/[^/]+$') {
                return $value
            }
        }
    }
    throw "Unsupported GitHub remote URL: $Url"
}

$resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$git = Get-Command git.exe -ErrorAction Stop
$gh = Get-Command gh.exe -ErrorAction Stop
$actualRoot = Invoke-NativeCommand -Executable $git.Source -Arguments @(
    '-C', $resolvedRoot, 'rev-parse', '--show-toplevel'
) -Description 'Git repository root query'
if (-not [IO.Path]::GetFullPath($actualRoot).Equals(
    [IO.Path]::GetFullPath($resolvedRoot),
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "The configured repository root does not match the Git worktree root: $actualRoot"
}

foreach ($remoteKind in @(
    @{ Name = 'fetch'; Arguments = @('remote', 'get-url', 'origin') },
    @{ Name = 'push'; Arguments = @('remote', 'get-url', '--push', 'origin') }
)) {
    $remoteUrl = Invoke-NativeCommand -Executable $git.Source `
        -Arguments (@('-C', $resolvedRoot) + $remoteKind.Arguments) `
        -Description "Git origin $($remoteKind.Name) URL query"
    $repositoryName = ConvertTo-GitHubRepositoryName -Url $remoteUrl
    if (-not $repositoryName.Equals(
        $expectedRepository, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Git origin targets '$repositoryName'; expected '$expectedRepository'."
    }
}

if ([string]::IsNullOrWhiteSpace($PushRemoteName) -ne
    [string]::IsNullOrWhiteSpace($PushRemoteUrl)) {
    throw 'Push remote name and URL must either both be provided or both be omitted.'
}
if (-not [string]::IsNullOrWhiteSpace($PushRemoteUrl)) {
    $pushRepositoryName = ConvertTo-GitHubRepositoryName -Url $PushRemoteUrl
    if (-not $pushRepositoryName.Equals(
        $expectedRepository, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Push destination '$PushRemoteName' targets '$pushRepositoryName'; expected '$expectedRepository'."
    }
}

$metadataJson = Invoke-NativeCommand -Executable $gh.Source -Arguments @(
    'repo', 'view', $expectedRepository,
    '--json', 'nameWithOwner,visibility,url'
) -Description 'GitHub repository visibility query'
$metadata = $metadataJson | ConvertFrom-Json
if ($metadata.visibility -ne 'PRIVATE') {
    throw "GitHub repository '$expectedRepository' is '$($metadata.visibility)', not 'PRIVATE'."
}

Write-Host "Private repository verified: $($metadata.nameWithOwner) ($($metadata.visibility))"
