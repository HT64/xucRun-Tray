<#
.SYNOPSIS
Enables the repository's version-controlled Git safety hooks.

.DESCRIPTION
Confirms that the script is running from the root of the current xucRun Tray
worktree, verifies that the pre-push hook and public-repository check exist,
sets the worktree-local core.hooksPath to .githooks, and immediately runs the
public-repository check. No global Git configuration is changed.

.EXAMPLE
.\Install-GitHooks.ps1

Enables the checked-in hooks for the current clone and verifies its public
origin and GitHub visibility.

.NOTES
Requires Git, GitHub CLI authentication usable by Test-PublicRepository.ps1,
and permission to update the worktree's local Git configuration. The script
changes .git\config for this clone. It accepts no parameters and does not
bypass or install hooks outside this worktree. Normal completion returns 0
when run with powershell.exe -File; missing safety files, a mismatched
worktree root, Git configuration failure, or repository verification failure
causes a terminating error and a nonzero PowerShell process exit code.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
$hookPath = Join-Path $repositoryRoot '.githooks\pre-push'
$repositoryCheck = Join-Path $repositoryRoot 'Test-PublicRepository.ps1'
foreach ($requiredFile in @($hookPath, $repositoryCheck)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required Git safety file was not found: $requiredFile"
    }
}

$actualRoot = (& git -C $repositoryRoot rev-parse --show-toplevel 2>&1 |
    ForEach-Object { $_.ToString() }) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not [IO.Path]::GetFullPath($actualRoot.Trim()).Equals(
    [IO.Path]::GetFullPath($repositoryRoot),
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The script is not located at the Git worktree root.'
}

& git -C $repositoryRoot config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw 'The version-controlled Git hook path could not be configured.'
}
& $repositoryCheck -RepositoryRoot $repositoryRoot
Write-Host 'Git safety hooks installed for this Tray clone: .githooks'
