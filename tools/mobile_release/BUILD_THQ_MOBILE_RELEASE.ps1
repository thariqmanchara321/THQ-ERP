param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectRoot,
    [ValidateSet("apk","appbundle","both")]
    [string]$Format = "both",
    [string]$OutputRoot = "",
    [switch]$SkipAnalyze
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if([string]::IsNullOrWhiteSpace($OutputRoot)){
    $OutputRoot = Join-Path $env:USERPROFILE "THQ_Releases\v6.2.7-build12"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

function Assert-SigningConfig {
    param(
        [string]$AppDir,
        [string]$AliasEnv,
        [string]$PasswordEnv
    )

    $props = Join-Path $AppDir "android\key.properties"
    if(Test-Path $props){
        $raw = [IO.File]::ReadAllText($props)
        foreach($key in @("storeFile","storePassword","keyAlias","keyPassword")){
            if($raw -notmatch "(?m)^$([regex]::Escape($key))=.+$"){
                throw "$props is missing $key"
            }
        }
        if($raw -match "CHANGE_ME|YOUR_USER"){
            throw "$props still contains placeholder values."
        }
        return
    }

    $required = @(
        "THQ_ANDROID_KEYSTORE_PATH",
        "THQ_ANDROID_KEYSTORE_PASSWORD",
        $AliasEnv,
        $PasswordEnv
    )
    $missing = @()
    foreach($name in $required){
        $value = [Environment]::GetEnvironmentVariable($name)
        if([string]::IsNullOrWhiteSpace($value)){ $missing += $name }
    }
    if($missing.Count -gt 0){
        throw "Production signing is not configured for $AppDir. Missing: $($missing -join ', '). Copy android\key.properties.example to android\key.properties or set the environment variables."
    }
}

function Invoke-Flutter {
    param([string]$AppDir,[string[]]$Args)
    Push-Location $AppDir
    try {
        & flutter @Args
        if($LASTEXITCODE -ne 0){
            throw "flutter $($Args -join ' ') failed in $AppDir"
        }
    } finally {
        Pop-Location
    }
}

$apps = @(
    @{
        Key="client_mobile"
        Dir=(Join-Path $ProjectRoot "apps\client_mobile")
        AliasEnv="THQ_CLIENT_KEY_ALIAS"
        PasswordEnv="THQ_CLIENT_KEY_PASSWORD"
        OutputBase="thq-client-mobile-v6.2.7-build12"
    },
    @{
        Key="mobile_pos"
        Dir=(Join-Path $ProjectRoot "apps\mobile_pos")
        AliasEnv="THQ_POS_KEY_ALIAS"
        PasswordEnv="THQ_POS_KEY_PASSWORD"
        OutputBase="thq-mobile-pos-v6.2.7-build12"
    }
)

foreach($app in $apps){
    Assert-SigningConfig -AppDir $app.Dir -AliasEnv $app.AliasEnv -PasswordEnv $app.PasswordEnv
}

if(-not $SkipAnalyze){
    Push-Location (Join-Path $ProjectRoot "packages\erp_core")
    try {
        & flutter test
        if($LASTEXITCODE -ne 0){ throw "flutter test failed: packages/erp_core" }
    } finally { Pop-Location }

    foreach($app in $apps){
        Invoke-Flutter -AppDir $app.Dir -Args @("pub","get")
        Invoke-Flutter -AppDir $app.Dir -Args @("analyze")
    }
}

$artifacts = @()
foreach($app in $apps){
    if($Format -eq "apk" -or $Format -eq "both"){
        Invoke-Flutter -AppDir $app.Dir -Args @("build","apk","--release")
        $src = Join-Path $app.Dir "build\app\outputs\flutter-apk\app-release.apk"
        if(-not (Test-Path $src)){ throw "Expected APK not found: $src" }
        $dst = Join-Path $OutputRoot ($app.OutputBase + ".apk")
        Copy-Item $src $dst -Force
        $artifacts += $dst
    }

    if($Format -eq "appbundle" -or $Format -eq "both"){
        Invoke-Flutter -AppDir $app.Dir -Args @("build","appbundle","--release")
        $src = Join-Path $app.Dir "build\app\outputs\bundle\release\app-release.aab"
        if(-not (Test-Path $src)){ throw "Expected AAB not found: $src" }
        $dst = Join-Path $OutputRoot ($app.OutputBase + ".aab")
        Copy-Item $src $dst -Force
        $artifacts += $dst
    }
}

$hashLines = foreach($artifact in $artifacts){
    $hash = (Get-FileHash $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($artifact))"
}
$hashFile = Join-Path $OutputRoot "SHA256SUMS.txt"
$hashLines | Set-Content -Path $hashFile -Encoding ascii

Write-Host ""
Write-Host "THQ signed mobile release artifacts created:" -ForegroundColor Green
foreach($artifact in $artifacts){ Write-Host "  $artifact" }
Write-Host "  $hashFile"
