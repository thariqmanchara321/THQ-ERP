$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Apps = @("admin_panel", "client_app", "pos_app")
foreach ($App in $Apps) {
    Write-Host "`n=== ANALYZE $App ===" -ForegroundColor Cyan
    Push-Location (Join-Path $Root "apps\$App")
    try {
        flutter pub get
        dart fix --apply
        dart format lib
        flutter analyze
    }
    finally {
        Pop-Location
    }
}
Write-Host "`nAll app analyzers completed." -ForegroundColor Green
