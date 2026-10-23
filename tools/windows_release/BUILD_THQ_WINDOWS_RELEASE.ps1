param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectRoot = "",

    [ValidateSet("client","pos","both")]
    [string]$TargetApp = "both",

    [ValidateSet("portable","installer","both")]
    [string]$Format = "both",

    [string]$Version = "",
    [int]$BuildNumber = 0,

    [string]$OutputRoot = "",
    [switch]$SkipAnalyze,
    [switch]$SkipVcRedist,
    [switch]$RequireSigning
)

$ErrorActionPreference = "Stop"
$ToolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if([string]::IsNullOrWhiteSpace($ProjectRoot) -or -not (Test-Path $ProjectRoot)){
    $ProjectRoot = Split-Path -Parent $ToolsRoot
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

# 1. Automatically detect version and build number if not explicitly provided
if([string]::IsNullOrWhiteSpace($Version) -or $BuildNumber -le 0){
    $contractFile = Join-Path $ProjectRoot "packages\erp_core\lib\src\release_contract.dart"
    if(Test-Path $contractFile){
        $content = Get-Content $contractFile -Raw
        if($content -match "appVersion\s*=\s*'([^']+)'"){
            if([string]::IsNullOrWhiteSpace($Version)){ $Version = $matches[1] }
        }
        if($content -match "buildNumber\s*=\s*([0-9]+)"){
            if($BuildNumber -le 0){ $BuildNumber = [int]$matches[1] }
        }
    }

    if([string]::IsNullOrWhiteSpace($Version) -or $BuildNumber -le 0){
        $pubspec = Join-Path $ProjectRoot "apps\client_app\pubspec.yaml"
        if(Test-Path $pubspec){
            $verLine = Get-Content $pubspec | Where-Object { $_ -match "^version:\s*([0-9.]+)\+([0-9]+)" } | Select-Object -First 1
            if($verLine -match "^version:\s*([0-9.]+)\+([0-9]+)"){
                if([string]::IsNullOrWhiteSpace($Version)){ $Version = $matches[1] }
                if($BuildNumber -le 0){ $BuildNumber = [int]$matches[2] }
            }
        }
    }
}

if([string]::IsNullOrWhiteSpace($Version)){ $Version = "8.1.0" }
if($BuildNumber -le 0){ $BuildNumber = 16 }

Write-Host "THQ ERP Windows Release Builder" -ForegroundColor Cyan
Write-Host "Version: $Version | Build: $BuildNumber | Target: $TargetApp | Format: $Format" -ForegroundColor Cyan

if([string]::IsNullOrWhiteSpace($OutputRoot)){
    $OutputRoot = Join-Path $ProjectRoot "build\windows_release"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Invoke-Flutter {
    param([string]$AppDir,[string[]]$FlutterArgs)
    Push-Location $AppDir
    try {
        & flutter @FlutterArgs
        if($LASTEXITCODE -ne 0){
            throw "flutter $($FlutterArgs -join ' ') failed in $AppDir"
        }
    } finally { Pop-Location }
}

function Find-ReleaseDir {
    param([string]$AppDir,[string]$ExeName)
    $windowsBuild = Join-Path $AppDir "build\windows"
    if(-not (Test-Path $windowsBuild)){
        throw "Windows build directory not found: $windowsBuild"
    }
    $exe = Get-ChildItem $windowsBuild -Recurse -File -Filter $ExeName -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq "Release" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if(-not $exe){
        throw "Release executable not found under ${windowsBuild}: $ExeName"
    }
    if($exe.FullName -notmatch '\\x64\\'){
        throw "Installer is x64-only, but detected output was: $($exe.FullName)"
    }
    return $exe.Directory.FullName
}

function Find-InnoCompiler {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if($cmd -and $cmd.Source){ return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach($c in $candidates){
        if(-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)){
            return $c
        }
    }
    throw "ISCC.exe was not found. Install Inno Setup 7 or 6, or add ISCC.exe to PATH."
}

function Test-SigningConfigured {
    return (
        -not [string]::IsNullOrWhiteSpace($env:THQ_WINDOWS_SIGN_PFX) -or
        -not [string]::IsNullOrWhiteSpace($env:THQ_WINDOWS_SIGN_THUMBPRINT)
    )
}

function Ensure-PfxPassword {
    if([string]::IsNullOrWhiteSpace($env:THQ_WINDOWS_SIGN_PFX)){ return }
    if(-not [string]::IsNullOrWhiteSpace($env:THQ_WINDOWS_SIGN_PASSWORD)){ return }

    $secure = Read-Host "Windows code-signing PFX password" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $env:THQ_WINDOWS_SIGN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

$signingConfigured = Test-SigningConfigured
if($RequireSigning -and -not $signingConfigured){
    throw "Production signing is required. Configure THQ_WINDOWS_SIGN_PFX or THQ_WINDOWS_SIGN_THUMBPRINT."
}
if($signingConfigured){
    if([string]::IsNullOrWhiteSpace($env:THQ_WINDOWS_TIMESTAMP_URL)){
        throw "THQ_WINDOWS_TIMESTAMP_URL is required when signing is enabled."
    }
    Ensure-PfxPassword
}
else {
    Write-Warning "No Windows Authenticode certificate configured. Artifacts will be UNSIGNED QA candidates. Use -RequireSigning for a fail-closed production build."
}

$allApps = @(
    @{
        Key = "client"
        Name = "THQ Business"
        Dir = Join-Path $ProjectRoot "apps\client_app"
        Exe = "thq_business.exe"
        Iss = Join-Path $ToolsRoot "THQ_Business.iss"
        PortableBase = "THQ-Business-v$Version-build$BuildNumber-windows-x64"
    },
    @{
        Key = "pos"
        Name = "THQ POS"
        Dir = Join-Path $ProjectRoot "apps\pos_app"
        Exe = "thq_pos.exe"
        Iss = Join-Path $ToolsRoot "THQ_POS.iss"
        PortableBase = "THQ-POS-v$Version-build$BuildNumber-windows-x64"
    }
)

$apps = $allApps | Where-Object { $TargetApp -eq "both" -or $_.Key -eq $TargetApp }

if(-not $SkipAnalyze){
    Push-Location (Join-Path $ProjectRoot "packages\erp_core")
    try {
        & flutter test
        if($LASTEXITCODE -ne 0){ throw "flutter test failed: packages/erp_core" }
    } finally { Pop-Location }

    foreach($app in $apps){
        Invoke-Flutter -AppDir $app.Dir -FlutterArgs @("pub","get")
        Invoke-Flutter -AppDir $app.Dir -FlutterArgs @("analyze")
    }
}

$vcRedist = $null
if(-not $SkipVcRedist){
    $prereqDir = Join-Path $OutputRoot "_prerequisites"
    New-Item -ItemType Directory -Force -Path $prereqDir | Out-Null
    $vcRedist = Join-Path $prereqDir "vc_redist.x64.exe"
    if(-not (Test-Path $vcRedist)){
        Write-Host "Downloading Microsoft Visual C++ x64 Redistributable..."
        Invoke-WebRequest "https://aka.ms/vc14/vc_redist.x64.exe" -OutFile $vcRedist
    }
    if((Get-Item $vcRedist).Length -lt 1MB){
        throw "Downloaded VC++ Redistributable is unexpectedly small."
    }
}

$artifacts = @()
$manifestEntries = @()
$inno = $null
if($Format -eq "installer" -or $Format -eq "both"){
    $inno = Find-InnoCompiler
}

# Copy update coordinator script to output directory for customer support & recovery
$coordSrc = Join-Path $ToolsRoot "thq_update_coordinator.ps1"
if(Test-Path $coordSrc){
    Copy-Item $coordSrc (Join-Path $OutputRoot "thq_update_coordinator.ps1") -Force
}

foreach($app in $apps){
    Write-Host ""
    Write-Host "=== Building $($app.Name) (v$Version+$BuildNumber) ===" -ForegroundColor Cyan

    Invoke-Flutter -AppDir $app.Dir -FlutterArgs @(
        "build","windows","--release",
        "--build-name",$Version,
        "--build-number",$BuildNumber.ToString()
    )

    $releaseDir = Find-ReleaseDir -AppDir $app.Dir -ExeName $app.Exe
    foreach($required in @($app.Exe,"flutter_windows.dll","data")){
        $requiredPath = Join-Path $releaseDir $required
        if(-not (Test-Path $requiredPath)){
            throw "Required Windows release component is missing: $requiredPath"
        }
    }

    if($signingConfigured){
        & (Join-Path $ToolsRoot "SIGN_WINDOWS_FILE.ps1") (Join-Path $releaseDir $app.Exe)
        if($LASTEXITCODE -ne 0){ throw "Signing failed for $($app.Exe)" }
    }

    $portableDir = Join-Path $OutputRoot $app.PortableBase
    if(Test-Path $portableDir){ Remove-Item $portableDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
    Copy-Item (Join-Path $releaseDir "*") $portableDir -Recurse -Force

    # Ensure update coordinator is bundled directly into the application directory ({app})
    $coordSrc = Join-Path $ToolsRoot "thq_update_coordinator.ps1"
    if(Test-Path $coordSrc){
        Copy-Item $coordSrc (Join-Path $portableDir "thq_update_coordinator.ps1") -Force
        if($signingConfigured){
            try {
                & (Join-Path $ToolsRoot "SIGN_WINDOWS_FILE.ps1") (Join-Path $portableDir "thq_update_coordinator.ps1")
            } catch {
                Write-Warning "Could not sign thq_update_coordinator.ps1: $_"
            }
        }
    }

    if($vcRedist){
        $portablePrereq = Join-Path $portableDir "Prerequisites"
        New-Item -ItemType Directory -Force -Path $portablePrereq | Out-Null
        Copy-Item $vcRedist (Join-Path $portablePrereq "vc_redist.x64.exe") -Force
    }

    if($Format -eq "portable" -or $Format -eq "both"){
        $zipPath = Join-Path $OutputRoot ($app.PortableBase + "-portable.zip")
        if(Test-Path $zipPath){ Remove-Item $zipPath -Force }
        Compress-Archive -Path (Join-Path $portableDir "*") -DestinationPath $zipPath -CompressionLevel Optimal
        $artifacts += $zipPath
    }

    if($Format -eq "installer" -or $Format -eq "both"){
        $isccArgs = @(
            "/DSourceDir=$portableDir",
            "/DOutputDir=$OutputRoot",
            "/DAppVersion=$Version",
            "/DBuildNumber=$BuildNumber"
        )
        if($vcRedist){ $isccArgs += "/DVcRedistPath=$vcRedist" }

        if($signingConfigured){
            $signScript = Join-Path $ToolsRoot "SIGN_WINDOWS_FILE.ps1"
            $signToolDef = 'thq=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $signScript + '" $f'
            $isccArgs += "/DEnableSigning=1"
            $isccArgs += "--signtool=$signToolDef"
        } else {
            $isccArgs += "--no-signing"
        }

        $isccArgs += $app.Iss
        & $inno @isccArgs
        if($LASTEXITCODE -ne 0){ throw "Inno Setup compilation failed: $($app.Name)" }

        $installer = Join-Path $OutputRoot ($app.PortableBase + ".exe")
        if(-not (Test-Path $installer)){
            throw "Expected installer was not created: $installer"
        }

        if($signingConfigured){
            $signature = Get-AuthenticodeSignature $installer
            if($signature.Status -ne "Valid"){
                throw "Installer signature is not valid: $($signature.Status) - $installer"
            }
        }
        $artifacts += $installer

        # Compute SHA256 and size for manifest
        $instItem = Get-Item $installer
        $instHash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestEntries += @{
            app_key = $app.Key
            platform = "windows"
            version = $Version
            build_number = $BuildNumber
            file_name = $instItem.Name
            file_size_bytes = $instItem.Length
            sha256 = $instHash
            installer_path = $installer
        }
    }
}

if($artifacts.Count -eq 0){ throw "No release artifacts were generated." }

$hashFile = Join-Path $OutputRoot "SHA256SUMS.txt"
$hashLines = foreach($artifact in $artifacts){
    $hash = (Get-FileHash $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($artifact))"
}
$hashLines | Set-Content $hashFile -Encoding ascii

$gitCommit = (& git -C $ProjectRoot rev-parse --short HEAD).Trim()

$manifestFile = Join-Path $OutputRoot "release_manifest.json"
$manifest = @{
    version = $Version
    build_number = $BuildNumber
    built_at = (Get-Date -Format o)
    git_commit = $gitCommit
    signed = $signingConfigured
    artifacts = $manifestEntries
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestFile -Encoding utf8

$releaseInfo = Join-Path $OutputRoot "RELEASE_INFO.txt"
@(
    "THQ ERP Windows v$Version Build $BuildNumber",
    "Release: Automatic Update System V2 Certified Build",
    "Built: $(Get-Date -Format o)",
    "Signing: $(if($signingConfigured){'Authenticode enabled'}else{'UNSIGNED'})",
    "VC++ Runtime bundled: $([bool]$vcRedist)",
    "Git HEAD: $gitCommit"
) | Set-Content $releaseInfo -Encoding utf8

Write-Host ""
Write-Host "THQ Windows release artifacts created:" -ForegroundColor Green
foreach($artifact in $artifacts){ Write-Host "  $artifact" }
Write-Host "  $hashFile"
Write-Host "  $manifestFile"
Write-Host "  $releaseInfo"

if(-not $signingConfigured){
    Write-Warning "These are unsigned candidates. For production distribution configure Authenticode signing and rerun with -RequireSigning."
}
