[CmdletBinding()]
param(
  [switch]$SkipUnitTests
)

$script = Join-Path $PSScriptRoot 'tools/environments/CHECK_THQ_TEST.ps1'
& $script @PSBoundParameters
exit $LASTEXITCODE
