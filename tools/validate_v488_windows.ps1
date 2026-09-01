param([switch]$Build)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$projects = @('apps/admin_panel','apps/client_app','apps/pos_app','apps/client_mobile','apps/mobile_pos','packages/erp_core')
foreach ($project in $projects) {
  Push-Location (Join-Path $Root $project)
  try {
    Write-Host "== $project ==" -ForegroundColor Cyan
    flutter pub get
    flutter analyze --fatal-infos --fatal-warnings
    flutter test
    if ($Build -and ($project -eq 'apps/client_mobile' -or $project -eq 'apps/mobile_pos')) { flutter build apk --release }
  } finally { Pop-Location }
}
Write-Host 'THQ ERP v4.8.8 validation complete.' -ForegroundColor Green
