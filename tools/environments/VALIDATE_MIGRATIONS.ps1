[CmdletBinding()]
param(
  [string]$MigrationDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir '../..')).Path

if (-not $MigrationDir) {
  $MigrationDir = Join-Path $root 'supabase/migrations'
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "       THQ ERP MIGRATION SAFETY VALIDATOR           " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

if (-not (Test-Path $MigrationDir)) {
  Write-Error "Migration directory not found: $MigrationDir"
  exit 1
}

$files = Get-ChildItem -Path $MigrationDir -Filter "*.sql" | Sort-Object Name
Write-Host "Found $($files.Count) migration files in $MigrationDir" -ForegroundColor Cyan

$hasErrors = $false
$seenTimestamps = @{}
$destructivePatterns = @(
  'DROP\s+TABLE\s+(?!IF\s+EXISTS\s+pg_temp)',
  'DROP\s+SCHEMA',
  'DROP\s+DATABASE',
  'TRUNCATE\s+TABLE',
  'TRUNCATE\s+(?!pg_temp)',
  'DELETE\s+FROM\s+\w+\s*;' # Unbounded delete without WHERE clause
)

$previousTimestamp = ""

foreach ($file in $files) {
  $name = $file.Name
  if ($name -match '^(\d{14})_(.+)\.sql$') {
    $timestamp = $matches[1]
    $description = $matches[2]

    # Check 1: Ordering
    if ($previousTimestamp -and ($timestamp -lt $previousTimestamp)) {
      Write-Host "  [FAIL] Order violation: $name is dated before previous ($previousTimestamp)" -ForegroundColor Red
      $hasErrors = $true
    }
    $previousTimestamp = $timestamp

    # Check 2: Duplicate Timestamps
    if ($seenTimestamps.ContainsKey($timestamp)) {
      Write-Host "  [FAIL] Duplicate timestamp ID detected: $timestamp" -ForegroundColor Red
      Write-Host "         Existing: $($seenTimestamps[$timestamp])" -ForegroundColor Red
      Write-Host "         Current : $name" -ForegroundColor Red
      $hasErrors = $true
    } else {
      $seenTimestamps[$timestamp] = $name
    }
  } else {
    Write-Host "  [WARN] File name does not follow standard 14-digit timestamp convention: $name" -ForegroundColor Yellow
  }

  # Check 3: Destructive SQL inspection
  $content = Get-Content $file.FullName -Raw
  foreach ($pattern in $destructivePatterns) {
    if ($content -match "(?im)$pattern") {
      Write-Host "  [WARN] Destructive SQL pattern detected in $($file.Name): '$pattern'" -ForegroundColor Yellow
    }
  }

  # Check 4: Accidental Production Reference
  if ($content -match 'yguzrxcdvyimjrfvtcvp') {
    Write-Host "  [FAIL] Production project reference (yguzrxcdvyimjrfvtcvp) hardcoded in migration: $($file.Name)" -ForegroundColor Red
    $hasErrors = $true
  }
}

if ($hasErrors) {
  Write-Host "====================================================" -ForegroundColor Red
  Write-Host "MIGRATION VALIDATION: FAILED (Errors detected)" -ForegroundColor Red
  Write-Host "====================================================" -ForegroundColor Red
  exit 1
} else {
  Write-Host "====================================================" -ForegroundColor Green
  Write-Host "MIGRATION VALIDATION: PASSED (All checks safe)" -ForegroundColor Green
  Write-Host "====================================================" -ForegroundColor Green
  exit 0
}
