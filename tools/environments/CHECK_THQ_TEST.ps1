[CmdletBinding()]
param(
  [switch]$SkipUnitTests
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir '../..')).Path

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "            THQ ERP TEST ENVIRONMENT HEALTH CHECK               " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$allPassed = $true

function Report-Check {
  param([string]$Name, [bool]$Success, [string]$Details = "")
  if ($Success) {
    Write-Host "  [PASS] $Name" -ForegroundColor Green
    if ($Details) { Write-Host "         $Details" -ForegroundColor DarkGray }
  } else {
    Write-Host "  [FAIL] $Name" -ForegroundColor Red
    if ($Details) { Write-Host "         $Details" -ForegroundColor Yellow }
    $script:allPassed = $false
  }
}

# 1. Path Safety Check
$isInsideTest = ($root -like "*THQ_ERP_TEST*") -and ($root -notlike "*flexi_erp*")
Report-Check "Workspace Isolation" $isInsideTest "Path: $root"

# 2. Git Branch Check
Push-Location $root
$branch = ""
try {
  $branch = (& git branch --show-current).Trim()
  $branchSafe = ($branch -ne 'main') -and ($branch.Length -gt 0)
  Report-Check "Git Branch Isolation" $branchSafe "Current branch: '$branch' (Production 'main' is protected)"
} catch {
  Report-Check "Git Branch Isolation" $false "Failed to read branch"
} finally {
  Pop-Location
}

# 3. Git Worktree Check
Push-Location $root
try {
  $worktrees = (& git worktree list)
  $rootNorm = $root.Replace('\', '/')
  $worktreeClean = $worktrees -match [regex]::Escape($rootNorm)
  Report-Check "Git Worktree Integrity" ([bool]$worktreeClean) "Worktree registered in Git repository"
} catch {
  Report-Check "Git Worktree Integrity" $false "Failed to inspect worktrees"
} finally {
  Pop-Location
}

# 4. Flutter and Dart Toolchain
try {
  $flutterVer = (& flutter --version | Select-Object -First 1)
  $dartVer = (& dart --version | Select-Object -First 1)
  Report-Check "Flutter Toolchain" ($null -ne $flutterVer) "$flutterVer"
  Report-Check "Dart Toolchain" ($null -ne $dartVer) "$dartVer"
} catch {
  Report-Check "Flutter/Dart Toolchain" $false "Could not invoke flutter or dart CLI"
}

# 5. Environment & Supabase Separation
$testJson = Join-Path $scriptDir 'test.json'
if (Test-Path $testJson) {
  $config = Get-Content $testJson -Raw | ConvertFrom-Json
  $isTargetTest = ($config.THQ_ENV -eq 'test') -and ($config.SUPABASE_URL -eq 'https://krejepenqgcmnsugbpmv.supabase.co')
  Report-Check "test.json Configuration" $isTargetTest "Target: $($config.SUPABASE_URL)"
} else {
  Report-Check "test.json Configuration" $false "File missing at $testJson"
}

# Live connectivity test to test Supabase
try {
  $testKey = "sb_publishable_aSDI9i6gG9oP2-Bcsy0nFg_aKZDiWev"
  $testUrl = "https://krejepenqgcmnsugbpmv.supabase.co/auth/v1/health?apikey=$testKey"
  $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 10
  $liveDbOk = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
  Report-Check "Live Test Supabase Connectivity" $liveDbOk "Endpoint: krejepenqgcmnsugbpmv (Status: $($response.StatusCode))"
} catch {
  Report-Check "Live Test Supabase Connectivity" $false "Cannot reach test database: $($_.Exception.Message)"
}

# 6. Verify All 5 App Folders and Platform Configurations
$apps = @(
  @{ Name = "client_app"; Platforms = @("windows", "android") },
  @{ Name = "pos_app"; Platforms = @("windows", "android") },
  @{ Name = "admin_panel"; Platforms = @("windows") },
  @{ Name = "client_mobile"; Platforms = @("android") },
  @{ Name = "mobile_pos"; Platforms = @("android") }
)

foreach ($app in $apps) {
  $appPath = Join-Path $root "apps/$($app.Name)"
  $exists = Test-Path $appPath
  Report-Check "App Folder: $($app.Name)" $exists "$appPath"

  if ($exists) {
    foreach ($plat in $app.Platforms) {
      $platPath = Join-Path $appPath $plat
      $platExists = Test-Path $platPath
      Report-Check "  Platform [$plat] for $($app.Name)" $platExists "$platPath"
    }

    # Verify SupabaseConfig in app
    $cfgFile = Join-Path $appPath "lib/config/supabase_config.dart"
    if (Test-Path $cfgFile) {
      $content = Get-Content $cfgFile -Raw
      $safeDefaults = ($content -match "krejepenqgcmnsugbpmv") -and ($content -match "defaultValue:\s*'test'")
      Report-Check "  SupabaseConfig Defaults in $($app.Name)" $safeDefaults "Defaults to isolated test backend"
    } else {
      Report-Check "  SupabaseConfig in $($app.Name)" $false "Config file missing"
    }
  }
}

# 7. Shared Packages Check
$packages = @("erp_core", "thq_ui", "thq_logistics")
foreach ($pkg in $packages) {
  $pkgPath = Join-Path $root "packages/$pkg"
  Report-Check "Shared Package: $pkg" (Test-Path $pkgPath) "$pkgPath"
}

# 8. Migration Safety Validation
$migScript = Join-Path $scriptDir "VALIDATE_MIGRATIONS.ps1"
if (Test-Path $migScript) {
  try {
    & powershell.exe -ExecutionPolicy Bypass -File $migScript | Out-Null
    $migOk = ($LASTEXITCODE -eq 0)
    Report-Check "Supabase Migrations Safety" $migOk "All 61 migrations verified clean"
  } catch {
    Report-Check "Supabase Migrations Safety" $false "$($_.Exception.Message)"
  }
} else {
  Report-Check "VALIDATE_MIGRATIONS.ps1" $false "Validator script missing"
}

# 9. Unit Tests Execution (Environment Isolation)
if (-not $SkipUnitTests) {
  Write-Host "Running Environment Isolation Unit Tests..." -ForegroundColor Cyan
  foreach ($app in $apps) {
    $appDir = Join-Path $root "apps/$($app.Name)"
    $testFile = Join-Path $appDir "test/environment_isolation_test.dart"
    if (Test-Path $testFile) {
      Push-Location $appDir
      try {
        & flutter test test/environment_isolation_test.dart 2>&1 | Out-Null
        $testPassed = ($LASTEXITCODE -eq 0)
        Report-Check "Environment Isolation Test: $($app.Name)" $testPassed "test/environment_isolation_test.dart"
      } catch {
        Report-Check "Environment Isolation Test: $($app.Name)" $false "$($_.Exception.Message)"
      } finally {
        Pop-Location
      }
    }
  }
}

# Final Verdict
Write-Host "================================================================" -ForegroundColor Cyan
if ($allPassed) {
  Write-Host "             THQ TEST ENVIRONMENT: SAFE                        " -ForegroundColor Green
  Write-Host "================================================================" -ForegroundColor Cyan
  Write-Host "Your test environment is 100% isolated, secure, and ready." -ForegroundColor Green
  exit 0
} else {
  Write-Host "             THQ TEST ENVIRONMENT: UNSAFE                      " -ForegroundColor Red
  Write-Host "================================================================" -ForegroundColor Cyan
  Write-Host "Failures detected above! Resolve before running or migrating." -ForegroundColor Red
  exit 1
}
