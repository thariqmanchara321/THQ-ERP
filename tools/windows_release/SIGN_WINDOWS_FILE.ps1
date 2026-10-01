param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$FilePath
)
$ErrorActionPreference = "Stop"

function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if($cmd){ return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach($root in $roots){
        $candidate = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\signtool.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if($candidate){ return $candidate }
    }
    throw "signtool.exe was not found. Install the Windows SDK / Visual Studio signing tools."
}

$target = (Resolve-Path $FilePath).Path
$timestamp = $env:THQ_WINDOWS_TIMESTAMP_URL
$pfx = $env:THQ_WINDOWS_SIGN_PFX
$password = $env:THQ_WINDOWS_SIGN_PASSWORD
$thumbprint = $env:THQ_WINDOWS_SIGN_THUMBPRINT
$machineStore = $env:THQ_WINDOWS_SIGN_MACHINE_STORE -eq "1"

if([string]::IsNullOrWhiteSpace($timestamp)){
    throw "THQ_WINDOWS_TIMESTAMP_URL is required for production signing."
}

$signtool = Find-SignTool
$args = @("sign","/fd","SHA256","/td","SHA256","/tr",$timestamp)

if(-not [string]::IsNullOrWhiteSpace($pfx)){
    $pfx = (Resolve-Path $pfx).Path
    if([string]::IsNullOrWhiteSpace($password)){
        throw "THQ_WINDOWS_SIGN_PASSWORD is required when THQ_WINDOWS_SIGN_PFX is used."
    }
    $args += @("/f",$pfx,"/p",$password)
}
elseif(-not [string]::IsNullOrWhiteSpace($thumbprint)){
    $args += @("/sha1",$thumbprint)
    if($machineStore){ $args += "/sm" }
}
else {
    throw "Configure THQ_WINDOWS_SIGN_PFX or THQ_WINDOWS_SIGN_THUMBPRINT."
}

$args += $target
& $signtool @args
if($LASTEXITCODE -ne 0){ throw "SignTool failed for $target" }

& $signtool verify /pa /v $target
if($LASTEXITCODE -ne 0){ throw "Signature verification failed for $target" }

Write-Host "SIGNED  $target" -ForegroundColor Green
