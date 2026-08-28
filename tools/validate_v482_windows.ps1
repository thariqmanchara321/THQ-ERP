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
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host 'THQ ERP v4.8.2 local Flutter release validation' -ForegroundColor Green
Write-Host "Root: $Root"
Write-Host 'Analyzer infos and warnings are fatal for this release.' -ForegroundColor Yellow

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
    Invoke-FlutterStep -Directory 'apps\client_app' -Arguments @('build','windows','--release') -Label 'Client release Windows build'
    Invoke-FlutterStep -Directory 'apps\pos_app' -Arguments @('build','windows','--release') -Label 'POS release Windows build'
}

Write-Host "`nTHQ ERP v4.8.2 Flutter validation completed successfully." -ForegroundColor Green
if (-not $Build) {
    Write-Host 'Run again with -Build to also create release builds.'
}
