[CmdletBinding()]
param(
  [switch]$Build
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir '../..')).Path
$appDir = Join-Path $root 'apps/mobile_pos'
$defines = Join-Path $scriptDir 'test.json'

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "        THQ ERP TEST LAUNCHER: Mobile POS           " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Path Safety Guard: Protect Production!
if ($root -like "*flexi_erp*") {
  Write-Error "CRITICAL SAFETY ERROR: Attempted to run TEST launcher inside production repository (flexi_erp)! Aborting immediately."
  exit 1
}

# 2. Branch Safety Guard
Push-Location $root
try {
  $branch = (& git branch --show-current).Trim()
  if ($branch -eq 'main') {
    Write-Error "CRITICAL SAFETY ERROR: Cannot run test launcher on production 'main' branch! Switch to 'staging' or a feature branch."
    exit 1
  }
  Write-Host "Git Branch: $branch (Verified Non-Production)" -ForegroundColor Green
} finally {
  Pop-Location
}

# 3. Environment Config Guard
if (-not (Test-Path $defines)) {
  Write-Error "Missing test definition file: $defines"
  exit 1
}
$config = Get-Content $defines -Raw | ConvertFrom-Json
if ($config.THQ_ENV -ne 'test' -or $config.SUPABASE_URL -ne 'https://krejepenqgcmnsugbpmv.supabase.co') {
  Write-Error "CRITICAL: test.json must point to assigned test database (krejepenqgcmnsugbpmv)."
  exit 1
}
Write-Host "Database Target: $($config.SUPABASE_URL) [ISOLATED TEST]" -ForegroundColor Green

# 4. Run App
Push-Location $appDir
try {
  if (-not (Test-Path (Join-Path $appDir '.dart_tool'))) {
    Write-Host "Running flutter pub get..." -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
  }

  $env:THQ_TEST_BUILD = '1'
  if ($Build) {
    Write-Host "Building Release APK for TEST..." -ForegroundColor Yellow
    flutter build apk --release "--dart-define-from-file=$defines"
  } else {
    Write-Host "Launching Mobile POS on Android (TEST Mode)..." -ForegroundColor Yellow
    flutter run "--dart-define-from-file=$defines"
  }
} finally {
  $env:THQ_TEST_BUILD = $null
  Pop-Location
}
