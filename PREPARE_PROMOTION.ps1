[CmdletBinding()]
param(
  [string]$TargetBranch = 'main',
  [string]$SourceBranch = '',
  [switch]$OpenGitHubPR
)

$script = Join-Path $PSScriptRoot 'tools/environments/PREPARE_PROMOTION.ps1'
& $script @PSBoundParameters
exit $LASTEXITCODE
