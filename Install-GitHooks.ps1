# Purpose: Activates the version-controlled safety hooks for this public Tray clone.
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
