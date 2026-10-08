[CmdletBinding()]
param(
  [string]$TargetBranch = 'main',
  [string]$SourceBranch = '',
  [switch]$SkipAnalyzer
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir '../..')).Path

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "          THQ ERP PROMOTION READINESS PRE-FLIGHT CHECK          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Push-Location $root
try {
  # 1. Workspace Safety Guard
  if ($root -like "*flexi_erp*") {
    Write-Error "CRITICAL SAFETY: Run CHECK_BEFORE_PROMOTE from TEST workspace, not production flexi_erp!"
    exit 1
  }

  if (-not $SourceBranch) {
    $SourceBranch = (& git branch --show-current).Trim()
  }
  Write-Host "Source Branch : $SourceBranch" -ForegroundColor Yellow
  Write-Host "Target Branch : $TargetBranch" -ForegroundColor Yellow
  Write-Host ""

  # 2. Check Git Cleanliness
  $dirty = (& git status --short)
  if ($dirty) {
    Write-Host "Git Working Tree Status: UNCOMMITTED CHANGES PRESENT" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
    Write-Host ""
  } else {
    Write-Host "Git Working Tree: CLEAN" -ForegroundColor Green
    Write-Host ""
  }

  # 3. Commits to be Promoted
  Write-Host "Commits to be Promoted ($TargetBranch..$SourceBranch):" -ForegroundColor Cyan
  $commits = (& git log "$TargetBranch..$SourceBranch" --oneline 2>$null)
  if ($commits) {
    $commits | ForEach-Object { Write-Host "  * $_" -ForegroundColor White }
  } else {
    Write-Host "  (No new commits between $TargetBranch and $SourceBranch)" -ForegroundColor Gray
  }
  Write-Host ""

  # 4. Changed Files and Stat
  Write-Host "Changes Summary:" -ForegroundColor Cyan
  $stat = (& git diff --stat "$TargetBranch...$SourceBranch" 2>$null)
  if ($stat) {
    $stat | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
  } else {
    Write-Host "  (No file changes detected)" -ForegroundColor Gray
  }
  Write-Host ""

  # 5. Apps & Packages Affected
  $changedFiles = (& git diff --name-only "$TargetBranch...$SourceBranch" 2>$null)
  $appsAffected = @()
  $allApps = @('client_app', 'pos_app', 'admin_panel', 'client_mobile', 'mobile_pos')
  foreach ($app in $allApps) {
    if ($changedFiles -match "^apps/$app/") {
      $appsAffected += $app
    }
  }
  $packagesAffected = @()
  $allPkgs = @('erp_core', 'thq_ui', 'thq_logistics')
  foreach ($pkg in $allPkgs) {
    if ($changedFiles -match "^packages/$pkg/") {
      $packagesAffected += $pkg
    }
  }

  Write-Host "Affected Applications:" -ForegroundColor Cyan
  if ($appsAffected.Count -gt 0) {
    $appsAffected | ForEach-Object { Write-Host "  [x] apps/$_" -ForegroundColor Yellow }
  } else {
    Write-Host "  [ ] None (no app modifications)" -ForegroundColor Gray
  }

  Write-Host "Affected Shared Packages:" -ForegroundColor Cyan
  if ($packagesAffected.Count -gt 0) {
    $packagesAffected | ForEach-Object { Write-Host "  [x] packages/$_" -ForegroundColor Yellow }
  } else {
    Write-Host "  [ ] None (no package modifications)" -ForegroundColor Gray
  }
  Write-Host ""

  # 6. Migrations Included
  $migrationFiles = $changedFiles | Where-Object { $_ -like "supabase/migrations/*.sql" }
  Write-Host "Database Migrations Included:" -ForegroundColor Cyan
  if ($migrationFiles) {
    $migrationFiles | ForEach-Object { Write-Host "  [MIGRATION] $_" -ForegroundColor Yellow }
    Write-Host "Validating migration integrity..." -ForegroundColor Cyan
    & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'VALIDATE_MIGRATIONS.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "Migration safety validation failed! Resolve migration issues before promotion."
    }
  } else {
    Write-Host "  [ ] None (schema unchanged)" -ForegroundColor Gray
  }
  Write-Host ""

  # 7. Code Analysis
  if (-not $SkipAnalyzer) {
    Write-Host "Running Static Analysis on Affected Modules..." -ForegroundColor Cyan
    $targetsToAnalyze = @()
    if ($appsAffected.Count -gt 0) {
      $targetsToAnalyze += ($appsAffected | ForEach-Object { "apps/$_" })
    } else {
      $targetsToAnalyze += "apps/client_app"
    }

    foreach ($target in $targetsToAnalyze) {
      Write-Host "Analyzing $target..." -ForegroundColor Cyan
      Push-Location (Join-Path $root $target)
      try {
        & flutter analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) {
          throw "Analysis failed in $target!"
        }
      } finally {
        Pop-Location
      }
    }
    Write-Host "Analyzer Status: PASSED" -ForegroundColor Green
    Write-Host ""
  }

  Write-Host "================================================================" -ForegroundColor Green
  Write-Host "          PRE-FLIGHT CHECK COMPLETE: READY FOR REVIEW           " -ForegroundColor Green
  Write-Host "================================================================" -ForegroundColor Green
  Write-Host "No destructive actions were performed. Review the summary above." -ForegroundColor Green
} finally {
  Pop-Location
}
