param(
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Invoke-FlutterStep {
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Label
    )
    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    Push-Location (Join-Path $Root $Directory)
    try {
        & flutter @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
    }
    finally { Pop-Location }
}

Write-Host 'THQ ERP v4.8.3 release validation' -ForegroundColor Green
Write-Host "Root: $Root"

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python is required for tools/verify_v483_release.py.' }

Write-Host "`n=== v4.8.3 static release verification ===" -ForegroundColor Cyan
if ($python.Name -eq 'py.exe' -or $python.Name -eq 'py') { & $python.Source -3 (Join-Path $Root 'tools\verify_v483_release.py') }
else { & $python.Source (Join-Path $Root 'tools\verify_v483_release.py') }
if ($LASTEXITCODE -ne 0) { throw 'v4.8.3 static verification failed.' }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter SDK was not found in PATH.' }

$projects = @(
    @{ Path = 'packages\erp_core'; Name = 'erp_core' },
    @{ Path = 'apps\admin_panel'; Name = 'Admin' },
    @{ Path = 'apps\client_app'; Name = 'Client' },
    @{ Path = 'apps\pos_app'; Name = 'POS' }
)

foreach ($project in $projects) {
    Invoke-FlutterStep -Directory $project.Path -Arguments @('pub','get') -Label "$($project.Name) pub get"
    Invoke-FlutterStep -Directory $project.Path -Arguments @('analyze','--fatal-infos','--fatal-warnings') -Label "$($project.Name) analyze"
    Invoke-FlutterStep -Directory $project.Path -Arguments @('test') -Label "$($project.Name) tests"
}

if ($Build) {
    Invoke-FlutterStep -Directory 'apps\admin_panel' -Arguments @('build','web','--release') -Label 'Admin release web build'
    Invoke-FlutterStep -Directory 'apps\client_app' -Arguments @('build','apk','--release') -Label 'Client release Android build'
    Invoke-FlutterStep -Directory 'apps\client_app' -Arguments @('build','windows','--release') -Label 'Client release Windows build'
    Invoke-FlutterStep -Directory 'apps\client_app' -Arguments @('build','web','--release') -Label 'Client release web build'
    Invoke-FlutterStep -Directory 'apps\pos_app' -Arguments @('build','apk','--release') -Label 'POS release Android build'
    Invoke-FlutterStep -Directory 'apps\pos_app' -Arguments @('build','windows','--release') -Label 'POS release Windows build'
}

Write-Host "`nTHQ ERP v4.8.3 validation completed successfully." -ForegroundColor Green
if (-not $Build) { Write-Host 'Run again with -Build to create release binaries.' }
