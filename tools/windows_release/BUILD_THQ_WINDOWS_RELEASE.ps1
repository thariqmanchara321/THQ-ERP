param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,
    [ValidateSet("portable","installer","both")]
    [string]$Format = "both",
    [string]$OutputRoot = "",
    [switch]$SkipAnalyze,
    [switch]$SkipVcRedist,
    [switch]$RequireSigning
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$ToolsRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if([string]::IsNullOrWhiteSpace($OutputRoot)){
    $OutputRoot = Join-Path $env:USERPROFILE "THQ_Releases\v6.1.6-build9-windows"
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
        throw "Build 9 installer is x64-only, but detected output was: $($exe.FullName)"
    }
    return $exe.Directory.FullName
}

function Find-InnoCompiler {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if($cmd){ return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    if($candidates.Count -gt 0){ return $candidates[0] }
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

$apps = @(
    @{
        Name = "THQ Business"
        Dir = Join-Path $ProjectRoot "apps\client_app"
        Exe = "thq_business.exe"
        Iss = Join-Path $ToolsRoot "THQ_Business.iss"
        PortableBase = "THQ-Business-v6.1.6-build9-windows-x64"
    },
    @{
        Name = "THQ POS"
        Dir = Join-Path $ProjectRoot "apps\pos_app"
        Exe = "thq_pos.exe"
        Iss = Join-Path $ToolsRoot "THQ_POS.iss"
        PortableBase = "THQ-POS-v6.1.6-build9-windows-x64"
    }
)

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
$inno = $null
if($Format -eq "installer" -or $Format -eq "both"){
    $inno = Find-InnoCompiler
}

foreach($app in $apps){
    Write-Host ""
    Write-Host "=== Building $($app.Name) ===" -ForegroundColor Cyan

    Invoke-Flutter -AppDir $app.Dir -FlutterArgs @(
        "build","windows","--release",
        "--build-name","6.1.6",
        "--build-number","9"
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
            "/DAppVersion=6.1.6",
            "/DBuildNumber=9"
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
    }
}

if($artifacts.Count -eq 0){ throw "No release artifacts were generated." }

$hashFile = Join-Path $OutputRoot "SHA256SUMS.txt"
$hashLines = foreach($artifact in $artifacts){
    $hash = (Get-FileHash $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($artifact))"
}
$hashLines | Set-Content $hashFile -Encoding ascii

$releaseInfo = Join-Path $OutputRoot "RELEASE_INFO.txt"
@(
    "THQ ERP Windows v6.1.6 Build 9",
    "Release: Customer Receipt Safety & Small Balance Round-off",
    "Built: $(Get-Date -Format o)",
    "Signing: $(if($signingConfigured){'Authenticode enabled'}else{'UNSIGNED'})",
    "VC++ Runtime bundled: $([bool]$vcRedist)",
    "Git HEAD: $((& git -C $ProjectRoot rev-parse --short HEAD).Trim())"
) | Set-Content $releaseInfo -Encoding utf8

Write-Host ""
Write-Host "THQ Windows release artifacts created:" -ForegroundColor Green
foreach($artifact in $artifacts){ Write-Host "  $artifact" }
Write-Host "  $hashFile"
Write-Host "  $releaseInfo"

if(-not $signingConfigured){
    Write-Warning "These are unsigned candidates. For production distribution configure Authenticode signing and rerun with -RequireSigning."
}
