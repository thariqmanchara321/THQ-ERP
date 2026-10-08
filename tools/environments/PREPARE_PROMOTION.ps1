[CmdletBinding()]
param(
  [string]$TargetBranch = 'main',
  [string]$SourceBranch = '',
  [switch]$OpenGitHubPR
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $scriptDir '../..')).Path

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "             THQ ERP CONTROLLED PROMOTION HELPER                " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Run Pre-flight Check
$checker = Join-Path $scriptDir 'CHECK_BEFORE_PROMOTE.ps1'
& powershell.exe -ExecutionPolicy Bypass -File $checker -TargetBranch $TargetBranch -SourceBranch $SourceBranch
if ($LASTEXITCODE -ne 0) {
  Write-Error "Pre-flight checks failed! Promotion aborted."
  exit 1
}

Push-Location $root
try {
  if (-not $SourceBranch) {
    $SourceBranch = (& git branch --show-current).Trim()
  }

  Write-Host ""
  Write-Host "================================================================" -ForegroundColor Cyan
  Write-Host "               SAFE PROMOTION INSTRUCTIONS                      " -ForegroundColor Cyan
  Write-Host "================================================================" -ForegroundColor Cyan
  Write-Host "To promote approved changes from [$SourceBranch] to [$TargetBranch]:" -ForegroundColor White
  Write-Host ""
  Write-Host "METHOD 1: Recommended GitHub Pull Request (Peer Review)" -ForegroundColor Green
  Write-Host "  1. Push your branch to GitHub:" -ForegroundColor White
  Write-Host "     git push origin $SourceBranch" -ForegroundColor Yellow
  Write-Host "  2. Review and merge via GitHub PR URL:" -ForegroundColor White
  $prUrl = "https://github.com/thariqmanchara321/THQ-ERP/compare/$TargetBranch...${SourceBranch}?expand=1"
  Write-Host "     $prUrl" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "METHOD 2: Fast-Forward Git Merge in Production Workspace" -ForegroundColor Green
  Write-Host "  Run ONLY when explicitly authorized inside D:\ERP\flexi_erp:" -ForegroundColor White
  Write-Host "     cd D:\ERP\flexi_erp" -ForegroundColor Yellow
  Write-Host "     git checkout $TargetBranch" -ForegroundColor Yellow
  Write-Host "     git pull --ff-only origin $TargetBranch" -ForegroundColor Yellow
  Write-Host "     git merge --ff-only $SourceBranch" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "DATABASE MIGRATION NOTICE:" -ForegroundColor Magenta
  Write-Host "  If migrations were included, test them thoroughly in TEST first." -ForegroundColor White
  Write-Host "  Production migrations must be applied deliberately to the production" -ForegroundColor White
  Write-Host "  Supabase project (yguzrxcdvyimjrfvtcvp) via Supabase Dashboard SQL editor." -ForegroundColor White
  Write-Host "================================================================" -ForegroundColor Cyan

  if ($OpenGitHubPR) {
    Write-Host "Opening GitHub comparison in browser..." -ForegroundColor Yellow
    Start-Process $prUrl
  }
} finally {
  Pop-Location
}
