param(
  [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [switch]$BuildMobileApk
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter is not on PATH. Open your usual Flutter PowerShell terminal.' }
if (-not (Test-Path (Join-Path $RepoPath 'apps\client_app\pubspec.yaml'))) { throw "ERP source not found at $RepoPath" }
function Invoke-Flutter([string]$Directory, [string[]]$Arguments) {
  Push-Location (Join-Path $RepoPath $Directory)
  try {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & flutter @Arguments
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { throw "Flutter failed in $Directory (exit $code). Stop here and send the output." }
  } finally { Pop-Location }
}
foreach ($directory in @('packages\erp_core', 'apps\client_app', 'apps\pos_app', 'apps\mobile_pos')) {
  Write-Host "Checking $directory" -ForegroundColor Cyan
  Invoke-Flutter $directory @('pub', 'get')
  Invoke-Flutter $directory @('analyze', '--no-fatal-infos')
  Invoke-Flutter $directory @('test')
}
foreach ($directory in @('apps\client_app', 'apps\pos_app')) {
  Invoke-Flutter $directory @('build', 'windows', '--debug')
}
if ($BuildMobileApk) { Invoke-Flutter 'apps\mobile_pos' @('build', 'apk', '--debug') }
Write-Host 'Tracking update checks and Windows builds passed. Launch your usual production ERP.' -ForegroundColor Green
