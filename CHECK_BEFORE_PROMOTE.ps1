[CmdletBinding()]
param(
  [string]$TargetBranch = 'main',
  [string]$SourceBranch = '',
  [switch]$SkipAnalyzer
)

$script = Join-Path $PSScriptRoot 'tools/environments/CHECK_BEFORE_PROMOTE.ps1'
& $script @PSBoundParameters
exit $LASTEXITCODE
