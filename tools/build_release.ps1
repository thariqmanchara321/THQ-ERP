$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "=== ADMIN PANEL: Web ===" -ForegroundColor Cyan
Push-Location (Join-Path $Root "apps\admin_panel")
flutter pub get
flutter analyze
flutter build web --release
Pop-Location

Write-Host "=== CLIENT ERP: Android ===" -ForegroundColor Cyan
Push-Location (Join-Path $Root "apps\client_app")
flutter pub get
flutter analyze
flutter build apk --release
Write-Host "=== CLIENT ERP: Windows ===" -ForegroundColor Cyan
flutter build windows --release
Write-Host "=== CLIENT ERP: Web ===" -ForegroundColor Cyan
flutter build web --release
Pop-Location

Write-Host "=== FLEXI POS: Android ===" -ForegroundColor Cyan
Push-Location (Join-Path $Root "apps\pos_app")
flutter pub get
flutter analyze
flutter build apk --release
Write-Host "=== FLEXI POS: Windows ===" -ForegroundColor Cyan
flutter build windows --release
Pop-Location

Write-Host "`nRelease builds completed. Review build output folders before distribution." -ForegroundColor Green
