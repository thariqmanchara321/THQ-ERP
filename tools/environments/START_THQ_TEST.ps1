param(
  [ValidateSet('client_app','pos_app','admin_panel','client_mobile','mobile_pos')]
  [string]$App = 'client_app',
  [ValidateSet('windows','android')][string]$Target = 'windows',
  [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
function Invoke-Checked([scriptblock]$Command) {
  & $Command
  if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}
Push-Location $root
$previousTestBuild = $env:THQ_TEST_BUILD
try {
  $branch = (& git branch --show-current).Trim()
  if ($LASTEXITCODE -ne 0 -or $branch -ne 'staging') {
    throw 'Run TEST only in the separate staging worktree. See docs/THQ_TEST_ENVIRONMENT.md.'
  }
  if ($App -eq 'admin_panel' -and $Target -eq 'android') { throw 'Admin is a desktop app.' }
  $defines = Join-Path $PSScriptRoot 'test.json'
  $config = Get-Content $defines -Raw | ConvertFrom-Json
  if ($config.THQ_ENV -ne 'test' -or $config.SUPABASE_URL -ne 'https://krejepenqgcmnsugbpmv.supabase.co') {
    throw 'TEST configuration must point at the assigned test project.'
  }
  $env:THQ_TEST_BUILD = '1'
  Push-Location (Join-Path $root "apps/$App")
  try {
    Invoke-Checked { flutter pub get }
    Invoke-Checked { flutter test test/environment_isolation_test.dart }
    if ($Build) {
      $buildTarget = if ($Target -eq 'android') { 'apk' } else { 'windows' }
      Invoke-Checked { flutter build $buildTarget --release "--dart-define-from-file=$defines" }
      Write-Host 'TEST build complete. Keep the full Windows Release folder together; use a separate TEST folder.'
    } elseif ($Target -eq 'android') {
      # Flutter asks which device to use if several Android devices are connected.
      Invoke-Checked { flutter run "--dart-define-from-file=$defines" }
    } else {
      Invoke-Checked { flutter run -d windows "--dart-define-from-file=$defines" }
    }
  } finally { Pop-Location }
} finally {
  $env:THQ_TEST_BUILD = $previousTestBuild
  Pop-Location
}
