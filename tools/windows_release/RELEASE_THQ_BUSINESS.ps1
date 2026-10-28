<#
.SYNOPSIS
    THQ Business One-Click Build and Release Automation Launcher

.DESCRIPTION
    Provides automated local builds, pre-flight release configuration checks,
    QA update publication via GitHub Actions, and release status viewing for THQ Business.

.MODES
    - BuildOnly:      Compiles local Inno Setup installer via BUILD_THQ_BUSINESS_SETUP.ps1 without publishing.
    - CheckRelease:   Inspects git branch, tags, registry records, and proposed next version without changes.
    - PublishQA:      Verifies clean tree, pushes workflow dispatch to GitHub Actions, monitors release, verifies discovery.
    - ViewLatest:     Inspects the currently active Supabase release and latest GitHub Actions workflow run.
    - Menu:           Interactive console menu (default when launched directly or via batch).

.EXAMPLE
    .\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode BuildOnly
    .\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode CheckRelease
    .\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode PublishQA
#>

[CmdletBinding()]
param(
    [ValidateSet("BuildOnly", "CheckRelease", "PublishQA", "ViewLatest", "Menu")]
    [string]$Mode = "Menu",

    [ValidateSet("client", "pos", "both")]
    [string]$App = "client",

    [string]$RepoRoot = "",
    [string]$OutputDir = "D:\ERP\THQ_Setup",
    [string]$InnoCompiler = "C:\Program Files\Inno Setup 7\ISCC.exe",
    [string]$BuildScript = "D:\ERP\THQ_Business_Inno_Setup_Source\BUILD_THQ_BUSINESS_SETUP.ps1",
    [string]$TargetDevice = "CLIENT-BC8AEE",
    [string]$Channel = "internal_test",
    [string]$BumpType = "auto_build",
    [string]$ReleaseNotes = "",
    [switch]$AllowDivergentBuild,
    [switch]$Force,
    [switch]$NonInteractive
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# Auto-detect repository root if not specified
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $candidateRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
    if (Test-Path (Join-Path $candidateRoot "apps\client_app\pubspec.yaml")) {
        $RepoRoot = $candidateRoot
    } else {
        $RepoRoot = "D:\ERP\flexi_erp"
    }
}
$RepoRoot = (Resolve-Path $RepoRoot).Path

# Constants and QA Policy
$QA_DEVICE_NAME = "CLIENT-BC8AEE"
$QA_DEVICE_UUID = "bc8aeec1-9bce-4935-b349-168caf9a7fa4"
$QA_TENANT_UUID = "a659b6de-885d-44ed-9fa7-93eefa7d47d2"
$QA_THUMBPRINT  = "2813DEE08CC4B318907D2F5243DF81DA95EF60A7"
$WORKFLOW_FILE  = ".github/workflows/thq-release-windows.yml"
$SUPABASE_URL   = "https://yguzrxcdvyimjrfvtcvp.supabase.co"
$SUPABASE_ANON  = "sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ"

function Find-InnoCompilerPath {
    param([string]$PreferredPath)
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path $PreferredPath)) {
        return (Resolve-Path $PreferredPath).Path
    }
    $candidates = @(
        "C:\Program Files\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    $fromPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($fromPath -and $fromPath.Source) { return $fromPath.Source }
    return $null
}

function Find-GhCliPath {
    $fromPath = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($fromPath -and $fromPath.Source) { return $fromPath.Source }
    $candidates = @(
        "C:\Program Files\GitHub CLI\gh.exe",
        "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
        "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Test-GhAuthentication {
    param([string]$GhPath)
    if ([string]::IsNullOrWhiteSpace($GhPath)) { return $false }
    try {
        $res = & $GhPath auth status 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
        # Check output for logged in confirmation
        if ($res -match "Logged in to github.com") { return $true }
    } catch {}
    return $false
}

function Read-LocalVersionInfo {
    $pubspecPath = Join-Path $RepoRoot "apps\client_app\pubspec.yaml"
    $version = "8.2.2"
    $buildNumber = 19
    if (Test-Path $pubspecPath) {
        $content = Get-Content $pubspecPath -Raw
        if ($content -match "(?m)^version:\s*['""]?(\d+\.\d+\.\d+)\+(\d+)['""]?") {
            $version = $matches[1]
            $buildNumber = [int]$matches[2]
        }
    }
    return [pscustomobject]@{
        Version = $version
        BuildNumber = $buildNumber
    }
}

function Invoke-ReleaseVersionCheck {
    param([string]$App = "client", [string]$Bump = "auto_build")
    $py = "python"
    $managePy = Join-Path $RepoRoot "tools\release\manage_version.py"
    if (-not (Test-Path $managePy)) {
        throw "manage_version.py not found at $managePy"
    }
    $output = & $py $managePy --app $App --bump-type $Bump --check 2>&1
    $exitCode = $LASTEXITCODE
    $jsonStr = ($output | Where-Object { $_ -notmatch "^\[WARN\]" }) -join "`n"
    try {
        $parsed = $jsonStr | ConvertFrom-Json
        return [pscustomobject]@{
            ExitCode = $exitCode
            Data = $parsed
            RawOutput = $output
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            Data = $null
            RawOutput = $output
        }
    }
}

function Query-SupabaseReleaseActive {
    param([string]$TargetApp = "client", [string]$DeviceId = $QA_DEVICE_UUID, [string]$TenantId = $QA_TENANT_UUID)
    try {
        $bodyObj = @{
            p_app_key = $(if ($TargetApp -eq "both") { "client" } else { $TargetApp })
            p_platform = "windows"
            p_channel = "stable"
            p_current_version = "1.0.0"
            p_current_build = 1
            p_device_id = $DeviceId
            p_tenant_id = $TenantId
        }
        $jsonBody = $bodyObj | ConvertTo-Json
        $headers = @{
            "apikey" = $SUPABASE_ANON
            "Authorization" = "Bearer $SUPABASE_ANON"
            "Content-Type" = "application/json"
        }
        $resp = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/rpc/app_release_check_v820" -Method Post -Body $jsonBody -Headers $headers -TimeoutSec 8
        return $resp
    } catch {
        return $null
    }
}

# =========================================================================
# MODE A: BuildOnly
# =========================================================================
function Invoke-BuildOnly {
    param([switch]$AllowDivergentBuild = $script:AllowDivergentBuild)
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " MODE A: BUILD THQ BUSINESS INSTALLER LOCALLY (BuildOnly)" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    # 1. Validate paths and tools
    Write-Host "[1/5] Validating build environment and paths..." -ForegroundColor DarkGray
    if (-not (Test-Path $RepoRoot)) {
        throw "Repository root does not exist: $RepoRoot"
    }
    if (-not (Test-Path $BuildScript)) {
        throw "Inno build script not found: $BuildScript. Pass -BuildScript or verify repository layout."
    }

    $compiler = Find-InnoCompilerPath $InnoCompiler
    if (-not $compiler) {
        throw "Inno Setup compiler (ISCC.exe) was not found at '$InnoCompiler' or standard paths. Install Inno Setup 7 or add ISCC.exe to PATH."
    }
    Write-Host "  Repository Root: $RepoRoot"
    Write-Host "  Inno Compiler:   $compiler"
    Write-Host "  Build Script:    $BuildScript"
    Write-Host "  Output Directory: $OutputDir"

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter is not on PATH. Please run in an environment where 'flutter' is available."
    }

    # 2. Inspect version and check for divergence
    $localVer = Read-LocalVersionInfo
    Write-Host "[2/5] Current local version: $($localVer.Version) (Build $($localVer.BuildNumber))" -ForegroundColor Cyan
    Write-Host "  (Local builds do not increment version numbers unnecessarily)" -ForegroundColor DarkGray
    $latestTag = (& git -C $RepoRoot tag -l "v*" | Sort-Object | Select-Object -Last 1)
    $isDivergent = $false
    if ($latestTag) {
        Write-Host "  Highest Release Tag:     $latestTag" -ForegroundColor DarkGray
        if ($latestTag -notmatch "v$($localVer.Version)\+$($localVer.BuildNumber)") {
            $isDivergent = $true
        }
    }

    if ($isDivergent) {
        if (-not $AllowDivergentBuild) {
            Write-Host ""
            Write-Host "========================================================================" -ForegroundColor Red
            Write-Host " ERROR: LOCAL WORKSPACE VERSION DIVERGES FROM LATEST RELEASE TAG" -ForegroundColor Red
            Write-Host "========================================================================" -ForegroundColor Red
            Write-Host "  Local Workspace Version: $($localVer.Version) (Build $($localVer.BuildNumber))"
            Write-Host "  Highest Release Tag:     $latestTag"
            Write-Host ""
            Write-Host "  FAIL-SAFE BLOCK: Building now would produce a stale artifact ($($localVer.Version)+$($localVer.BuildNumber))" -ForegroundColor Red
            Write-Host "  that does not reflect released version $latestTag." -ForegroundColor Red
            Write-Host ""
            Write-Host "  To deliberately compile from local workspace source without syncing release tags," -ForegroundColor Yellow
            Write-Host "  rerun with the explicit override flag:" -ForegroundColor Yellow
            Write-Host "    .\tools\windows_release\RELEASE_THQ_BUSINESS.ps1 -Mode BuildOnly -AllowDivergentBuild" -ForegroundColor Yellow
            Write-Host "========================================================================" -ForegroundColor Red
            throw "Build halted: Local workspace ($($localVer.Version)+$($localVer.BuildNumber)) diverges from release tag ($latestTag). Pass -AllowDivergentBuild to compile local source deliberately."
        } else {
            Write-Host "========================================================================" -ForegroundColor Yellow
            Write-Host " NOTICE: EXPLICIT OVERRIDE ACTIVE (-AllowDivergentBuild)" -ForegroundColor Yellow
            Write-Host " Compiling local workspace source: $($localVer.Version) (Build $($localVer.BuildNumber))" -ForegroundColor Yellow
            Write-Host " Release Baseline in Git:        $latestTag" -ForegroundColor Yellow
            Write-Host " The resulting installer will contain local code, NOT the release baseline." -ForegroundColor Yellow
            Write-Host "========================================================================" -ForegroundColor Yellow
        }
    }

    # 3. Prepare output directory & log
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $OutputDir "thq_build_log_$timestamp.txt"
    Write-Host "[3/5] Starting build. Preserving build log to: $logFile" -ForegroundColor DarkGray

    # 4. Invoke BUILD_THQ_BUSINESS_SETUP.ps1
    Write-Host "[4/5] Executing Inno Setup compilation via existing build script..." -ForegroundColor Cyan
    $buildDir = Split-Path -Parent $BuildScript
    
    $procArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $BuildScript,
        "-RepoRoot", $RepoRoot,
        "-OutputDir", $OutputDir,
        "-InnoCompiler", $compiler
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $buildDir
    try {
        & powershell.exe @procArgs 2>&1 | Tee-Object -FilePath $logFile
        $buildExit = $LASTEXITCODE
    } finally {
        Pop-Location
        $sw.Stop()
    }

    if ($buildExit -ne 0) {
        throw "BUILD FAILED with exit code $buildExit. Inspect the build log at: $logFile"
    }

    # 5. Verify output installer
    Write-Host "[5/5] Verifying generated installer artifact..." -ForegroundColor Cyan
    $expectedName = "THQ_Business_Setup_v$($localVer.Version)_Build$($localVer.BuildNumber).exe"
    $setupExe = Join-Path $OutputDir $expectedName
    if (-not (Test-Path $setupExe)) {
        # Fallback search for newest setup exe in OutputDir
        $setupExe = Get-ChildItem -Path $OutputDir -Filter "THQ_Business_Setup_*.exe" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $setupExe -or -not (Test-Path $setupExe)) {
        throw "Expected installer was not found in $OutputDir after build completion. Inspect $logFile"
    }

    $fileItem = Get-Item $setupExe
    $hash = (Get-FileHash $setupExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $sizeMB = [math]::Round($fileItem.Length / 1MB, 2)

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host " THQ BUSINESS LOCAL BUILD COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "  Installer:    $setupExe"
    Write-Host "  Version:      $($localVer.Version)"
    Write-Host "  Build Number: $($localVer.BuildNumber)"
    Write-Host "  File Size:    $($fileItem.Length) bytes ($sizeMB MB)"
    Write-Host "  SHA-256:      $hash"
    Write-Host "  Build Time:   $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
    Write-Host "  Build Log:    $logFile"
    if ($isDivergent) {
        Write-Host "  ----------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "  SOURCE OVERRIDE: Built with -AllowDivergentBuild flag." -ForegroundColor Yellow
        Write-Host "  EXACT COMPILED SOURCE:   v$($localVer.Version)+$($localVer.BuildNumber)" -ForegroundColor Yellow
        Write-Host "  LATEST RELEASE BASELINE: $latestTag" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------------------" -ForegroundColor Yellow
    }
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host "Safety Guarantee: No network calls were made. No live release records modified." -ForegroundColor DarkGray
    return 0
}

# =========================================================================
# MODE B: CheckRelease
# =========================================================================
function Invoke-CheckRelease {
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " MODE B: CHECK RELEASE VERSION & CONFIGURATION (CheckRelease)" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    # 1. Git branch and working tree
    Write-Host "[1/6] Inspecting Git status and working-tree..." -ForegroundColor DarkGray
    $branch = (& git -C $RepoRoot branch --show-current).Trim()
    $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    $shortCommit = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
    $commitMsg = (& git -C $RepoRoot log -1 --format="%s").Trim()
    $rawPorcelain = & git -C $RepoRoot status --porcelain
    $porcelain = if ($rawPorcelain) { ($rawPorcelain -join "`n").Trim() } else { "" }
    $isDirty = -not [string]::IsNullOrWhiteSpace($porcelain)

    Write-Host "  Git Branch:    $branch"
    Write-Host "  Git Commit:    $shortCommit ($commitMsg)"
    if ($isDirty) {
        Write-Host "  Working Tree:  DIRTY (Uncommitted changes present)" -ForegroundColor Yellow
        $lines = ($porcelain -split "`n").Count
        Write-Host "                 $lines file(s) modified or untracked." -ForegroundColor Yellow
    } else {
        Write-Host "  Working Tree:  CLEAN (Ready for release)" -ForegroundColor Green
    }

    # Check if local commit is pushed to remote
    $remoteRef = & git -C $RepoRoot rev-parse --verify "origin/$branch" 2>$null
    $isPushed = ($remoteRef -and $remoteRef.Trim() -eq $commit)
    if ($isPushed) {
        Write-Host "  Remote Sync:   PUSHED to origin/$branch" -ForegroundColor Green
    } else {
        Write-Host "  Remote Sync:   NOT PUSHED or diverges from origin/$branch" -ForegroundColor Yellow
        Write-Host "                 Note: GitHub Actions release runs strictly against commits on origin." -ForegroundColor Yellow
    }

    # 2. Inspect Git tags
    Write-Host "[2/6] Inspecting Git release tags..." -ForegroundColor DarkGray
    $localTags = & git -C $RepoRoot tag -l "v*"
    $tagCount = ($localTags | Where-Object { $_ -match "^v\d" }).Count
    Write-Host "  Found $tagCount local release tags."

    # 3. Query Supabase & manage_version.py
    Write-Host "[3/6] Querying Supabase release registry & computing version..." -ForegroundColor DarkGray
    $verCheck = Invoke-ReleaseVersionCheck -App $App -Bump $BumpType

    if ($verCheck.ExitCode -ne 0 -or -not $verCheck.Data) {
        Write-Host "  [ERROR] Version check failed: $($verCheck.RawOutput)" -ForegroundColor Red
        return 1
    }

    $d = $verCheck.Data
    Write-Host "  Local Pubspec Version:   $($d.local_version) (Build $($d.local_build))"
    Write-Host "  Remote Published Version: $($d.remote_latest_version) (Build $($d.remote_latest_build))"
    Write-Host "  Git Highest Release Tag:  $($d.git_latest_version) (Build $($d.git_latest_build))"

    if ($d.discrepancy) {
        Write-Host "  Registry/Tag Notice:     $($d.discrepancy)" -ForegroundColor Yellow
    }

    if ($d.sources_checked) {
        Write-Host "  Sources Inspected:" -ForegroundColor DarkGray
        Write-Host "    - Local Git Tags:               $($d.sources_checked.local_git_tags)"
        Write-Host "    - Remote Git Tags:              $($d.sources_checked.remote_git_tags)"
        Write-Host "    - Latest Release RPC:           $(if ($d.sources_checked.registry_rpc) { 'Queried' } else { 'Not queried' })"
        Write-Host "    - Authenticated Registry Table: $(if ($d.sources_checked.registry_table_authenticated) { 'Verified' } else { 'Not queried (requires CI service-role credential)' })"
    }

    # 4. Proposed version calculation & collision check
    Write-Host "[4/6] Verifying version uniqueness policy & publication readiness..." -ForegroundColor DarkGray
    if ($d.collision_detected) {
        Write-Host "  [COLLISION DETECTED] $($d.error)" -ForegroundColor Red
        Write-Host "  Uniqueness policy: Each release MUST have a unique (app_key, platform, version)." -ForegroundColor Red
    } else {
        Write-Host "  Proposed Next Version:   $($d.proposed_version)" -ForegroundColor Green
        Write-Host "  Proposed Next Build:     $($d.proposed_build)" -ForegroundColor Green
        Write-Host "  Proposed Git Tag:        $($d.proposed_tag)" -ForegroundColor Green
        Write-Host "  Candidate Valid:         $(if ($d.candidate_valid) { 'YES' } else { 'NO' })" -ForegroundColor $(if ($d.candidate_valid) { 'Green' } else { 'Red' })
        Write-Host "  Branch In Sync:          $(if ($d.branch_in_sync) { 'YES' } else { 'NO (Local workspace behind remote/tag baseline)' })" -ForegroundColor $(if ($d.branch_in_sync) { 'Green' } else { 'Yellow' })
        if (-not $d.branch_in_sync -and $d.branch_divergence_diagnostic) {
            Write-Host "                           $($d.branch_divergence_diagnostic)" -ForegroundColor Yellow
        }
        Write-Host "  Complete Scan Verified:  $(if ($d.complete_registry_verified) { 'YES (Full table verified)' } else { 'NO (Provisional - Requires CI service-role credential)' })" -ForegroundColor $(if ($d.complete_registry_verified) { 'Green' } else { 'Yellow' })
        Write-Host "  Publication Ready:       $(if ($d.publication_ready) { 'YES' } else { 'NO (Complete registry scan unverified in local read-only check)' })" -ForegroundColor $(if ($d.publication_ready) { 'Green' } else { 'Yellow' })
        Write-Host "  Uniqueness Check:        PASSED (No collision with known registry records or tags)" -ForegroundColor Green
    }

    # 5. Validate GitHub CLI
    Write-Host "[5/6] Validating GitHub CLI (gh.exe) & authentication..." -ForegroundColor DarkGray
    $ghPath = Find-GhCliPath
    $ghAuthed = $false
    if ($ghPath) {
        $ghAuthed = Test-GhAuthentication $ghPath
        $ghVer = (& $ghPath --version | Select-Object -First 1).Trim()
        Write-Host "  GitHub CLI:    $ghPath"
        Write-Host "  CLI Version:   $ghVer"
        if ($ghAuthed) {
            Write-Host "  CLI Auth:      AUTHENTICATED (Ready for workflow dispatch)" -ForegroundColor Green
        } else {
            Write-Host "  CLI Auth:      NOT LOGGED IN" -ForegroundColor Yellow
            Write-Host "                 Run 'gh auth login' before triggering QA publication." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  GitHub CLI:    NOT FOUND" -ForegroundColor Yellow
        Write-Host "                 Install from https://cli.github.com/ to trigger QA releases automatically." -ForegroundColor Yellow
    }

    # 6. Validate Release Workflow & QA Safety Policy
    Write-Host "[6/6] Checking QA security policy & workflow prerequisites..." -ForegroundColor DarkGray
    $wfPath = Join-Path $RepoRoot $WORKFLOW_FILE
    if (Test-Path $wfPath) {
        Write-Host "  Release Workflow:        $WORKFLOW_FILE (Found)" -ForegroundColor Green
    } else {
        Write-Host "  Release Workflow:        MISSING at $wfPath" -ForegroundColor Red
    }
    Write-Host "  Target QA Device:        $QA_DEVICE_NAME ($QA_DEVICE_UUID)"
    Write-Host "  Target QA Tenant:        $QA_TENANT_UUID"
    Write-Host "  Required QA Thumbprint:  $QA_THUMBPRINT"
    Write-Host "  Release Channel:         $Channel"

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " PRE-FLIGHT RELEASE CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    $isPubReady = ($d.publication_ready -and -not $isDirty -and $isPushed -and $ghAuthed)
    $statusColor = if ($isPubReady) { "Green" } else { "Yellow" }
    Write-Host "  Candidate Calculation: Valid ($($d.proposed_version)+$($d.proposed_build)) $(if ($d.provisional_calculation) { '[Provisional - Local scan]' } else { '[Verified]' })" -ForegroundColor Cyan
    Write-Host "  Branch In Sync:        $(if ($d.branch_in_sync) { 'YES' } else { 'NO (Local workspace behind release baseline)' })" -ForegroundColor $(if ($d.branch_in_sync) { 'Green' } else { 'Yellow' })
    Write-Host "  Publication Ready Now: $(if ($isPubReady) { 'YES' } else { 'NO (Pre-flight checks require CI authenticated run & clean branch)' })" -ForegroundColor $statusColor
    Write-Host "  Proposed Version:      $($d.proposed_version) (Build $($d.proposed_build))"
    Write-Host "  Target Workflow:       $WORKFLOW_FILE"
    Write-Host "  Target Device:         $QA_DEVICE_NAME"
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Safety Guarantee: No tags created, no commits made, no database rows altered." -ForegroundColor DarkGray
    return 0
}

# =========================================================================
# MODE C: PublishQA
# =========================================================================
function Invoke-PublishQA {
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " MODE C: PUBLISH QA UPDATE VIA GITHUB ACTIONS (PublishQA)" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    # 1. Pre-flight verification
    Write-Host "[1/6] Running release pre-flight verifications..." -ForegroundColor DarkGray
    $branch = (& git -C $RepoRoot branch --show-current).Trim()
    $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    $shortCommit = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
    $commitMsg = (& git -C $RepoRoot log -1 --format="%s").Trim()

    # Dirty check: release MUST be clean
    $rawPorcelain = & git -C $RepoRoot status --porcelain
    $porcelain = if ($rawPorcelain) { ($rawPorcelain -join "`n").Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($porcelain)) {
        Write-Host "ERROR: Working tree has uncommitted modifications. A release cannot be initiated from a dirty tree." -ForegroundColor Red
        & git -C $RepoRoot status -s
        throw "Fail-Closed: Working tree is dirty. Commit or stash your changes before publishing."
    }

    # Pushed check: GitHub Actions checks out from origin
    $remoteRef = & git -C $RepoRoot rev-parse --verify "origin/$branch" 2>$null
    if (-not $remoteRef -or $remoteRef.Trim() -ne $commit) {
        throw "Fail-Closed: Local commit $shortCommit has not been pushed to origin/$branch. Push your branch first: 'git push origin $branch'."
    }

    # GitHub CLI check
    $ghPath = Find-GhCliPath
    if (-not $ghPath) {
        throw "Fail-Closed: GitHub CLI (gh.exe) is required to trigger release workflow. Install from https://cli.github.com/."
    }
    if (-not (Test-GhAuthentication $ghPath)) {
        throw "Fail-Closed: GitHub CLI is not logged in. Run 'gh auth login' to authenticate before releasing."
    }

    # 2. Calculate next version and check uniqueness
    Write-Host "[2/6] Determining next valid version and atomic build number..." -ForegroundColor DarkGray
    $verCheck = Invoke-ReleaseVersionCheck -App $App -Bump $BumpType
    if ($verCheck.ExitCode -ne 0 -or -not $verCheck.Data -or $verCheck.Data.collision_detected) {
        throw "Fail-Closed: Version determination failed or collision detected: $($verCheck.Data.error)"
    }
    $d = $verCheck.Data
    $proposedVer = $d.proposed_version
    $proposedBuild = $d.proposed_build
    $proposedTag = $d.proposed_tag

    # 3. Final confirmation
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host " PLEASE CONFIRM QA RELEASE PUBLICATION" -ForegroundColor Yellow
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "  Application:      client (THQ Business Windows x64)"
    Write-Host "  Branch:           $branch"
    Write-Host "  Commit:           $shortCommit ($commitMsg)"
    Write-Host "  Proposed Version: $proposedVer" -ForegroundColor Green
    Write-Host "  Proposed Build:   $proposedBuild" -ForegroundColor Green
    Write-Host "  Proposed Tag:     $proposedTag" -ForegroundColor Green
    Write-Host "  Release Channel:  $Channel"
    Write-Host "  Target Device:    $QA_DEVICE_NAME ($QA_DEVICE_UUID)" -ForegroundColor Cyan
    Write-Host "  Target Tenant:    $QA_TENANT_UUID"
    Write-Host "  Workflow:         $WORKFLOW_FILE"
    Write-Host "========================================================================" -ForegroundColor Yellow

    if (-not $Force -and -not $NonInteractive) {
        $confirm = Read-Host "Type 'YES' to trigger this release workflow on GitHub Actions"
        if ($confirm.Trim().ToUpper() -ne "YES") {
            Write-Host "Release publication aborted by user. No action was taken." -ForegroundColor Yellow
            return 0
        }
    }

    # 4. Trigger workflow dispatch
    Write-Host "[3/6] Triggering GitHub Actions workflow ($WORKFLOW_FILE)..." -ForegroundColor Cyan
    $appName = if ($App -eq "pos") { "THQ POS" } elseif ($App -eq "both") { "THQ ERP (Business & POS)" } else { "THQ Business" }
    $wfNotes = if (-not [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
        $ReleaseNotes
    } else {
        "$appName v$proposedVer (Build $proposedBuild) QA Automated Release"
    }

    $wfArgs = @(
        "workflow", "run", "thq-release-windows.yml",
        "--ref", $branch,
        "-f", "app=$App",
        "-f", "bump_type=$BumpType",
        "-f", "channel=$Channel",
        "-f", "target_device=$TargetDevice",
        "-f", "release_notes=$wfNotes"
    )

    & $ghPath @wfArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to trigger GitHub Actions release workflow via GitHub CLI."
    }
    Write-Host "Workflow dispatch triggered successfully." -ForegroundColor Green

    # 5. Locate and monitor the triggered run
    Write-Host "[4/6] Locating newly dispatched workflow run..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 4
    $runId = $null
    $runUrl = $null
    for ($i = 0; $i -lt 12; $i++) {
        $runsJson = & $ghPath run list --workflow="thq-release-windows.yml" --limit=3 --json databaseId,status,conclusion,url,createdAt 2>$null
        if ($runsJson) {
            $runs = $runsJson | ConvertFrom-Json
            if ($runs -and $runs.Count -gt 0) {
                $runId = $runs[0].databaseId
                $runUrl = $runs[0].url
                break
            }
        }
        Start-Sleep -Seconds 3
    }

    if ($runId) {
        Write-Host "  Workflow Run ID:  $runId" -ForegroundColor Cyan
        Write-Host "  Workflow URL:     $runUrl" -ForegroundColor Cyan
        Write-Host "[5/6] Monitoring workflow execution (press Ctrl+C to stop following; the run continues on GitHub)..." -ForegroundColor DarkGray
        
        try {
            & $ghPath run watch $runId --interval 10
            $finalRun = & $ghPath run view $runId --json status,conclusion | ConvertFrom-Json
            $conclusion = $finalRun.conclusion
        } catch {
            Write-Warning "Watch interrupted. Run is continuing remotely at: $runUrl"
            $conclusion = "unknown"
        }
    } else {
        Write-Host "Notice: Dispatched workflow is queued. Inspect runs at: https://github.com/thariqmanchara321/THQ-ERP/actions"
        $conclusion = "dispatched"
    }

    # 6. Post-publication verification
    Write-Host "[6/6] Verifying release discovery on authorized QA device..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 3
    $discovery = Query-SupabaseReleaseActive -DeviceId $QA_DEVICE_UUID -TenantId $QA_TENANT_UUID
    if ($discovery -and $discovery.update_available -and $discovery.latest_build -eq $proposedBuild) {
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor Green
        Write-Host " QA RELEASE PUBLISHED & VERIFIED SUCCESSFULLY" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor Green
        Write-Host "  Version:          $($discovery.latest_version)"
        Write-Host "  Build Number:     $($discovery.latest_build)"
        Write-Host "  Download URL:     $($discovery.download_url)"
        Write-Host "  SHA-256:          $($discovery.sha256_checksum)"
        Write-Host "  Package Size:     $($discovery.package_size_bytes) bytes"
        Write-Host "  Authorized QA:    $QA_DEVICE_NAME (Discovery verified)"
        Write-Host "  Workflow URL:     $runUrl"
        Write-Host "========================================================================" -ForegroundColor Green
    } else {
        Write-Host "Advisory: Workflow conclusion is '$conclusion'. If the build is still running or newly queued, verify discovery via ViewLatest once complete." -ForegroundColor Yellow
        if ($runUrl) { Write-Host "Workflow URL: $runUrl" }
    }
    return 0
}

# =========================================================================
# MODE D: ViewLatest
# =========================================================================
function Invoke-ViewLatest {
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host " MODE D: VIEW LATEST RELEASE & WORKFLOW RESULTS (ViewLatest)" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    # 1. Supabase Registry Active Release
    Write-Host "[1/3] Querying Supabase registry for App: $App, QA device $QA_DEVICE_NAME..." -ForegroundColor DarkGray
    $rel = Query-SupabaseReleaseActive -TargetApp $App -DeviceId $QA_DEVICE_UUID -TenantId $QA_TENANT_UUID
    if ($rel) {
        Write-Host "  Active Version:    $($rel.latest_version)" -ForegroundColor Green
        Write-Host "  Active Build:      $($rel.latest_build)" -ForegroundColor Green
        Write-Host "  Channel:           $($rel.channel)"
        Write-Host "  Released At:       $($rel.released_at)"
        Write-Host "  Update Available:  $($rel.update_available)"
        Write-Host "  SHA-256:           $($rel.sha256_checksum)"
        Write-Host "  Package Size:      $($rel.package_size_bytes) bytes"
        Write-Host "  Download URL:      $($rel.download_url)"
        Write-Host "  Release Notes:     $($rel.release_notes)"
    } else {
        Write-Host "  Could not query active release or no release currently targeted to $QA_DEVICE_NAME." -ForegroundColor Yellow
    }

    # 2. Latest GitHub Actions Workflow Runs
    Write-Host "[2/3] Checking latest GitHub Actions release workflow runs..." -ForegroundColor DarkGray
    $ghPath = Find-GhCliPath
    if ($ghPath -and (Test-GhAuthentication $ghPath)) {
        try {
            & $ghPath run list --workflow="thq-release-windows.yml" --limit=3
        } catch {
            Write-Host "  Could not retrieve runs: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  GitHub CLI not available or not logged in. Visit https://github.com/thariqmanchara321/THQ-ERP/actions" -ForegroundColor Yellow
    }

    # 3. Recent Git Release Tags
    Write-Host "[3/3] Inspecting recent Git release tags..." -ForegroundColor DarkGray
    $tags = & git -C $RepoRoot tag -l "v*" | Sort-Object | Select-Object -Last 5
    if ($tags) {
        foreach ($t in $tags) {
            $tagCommit = (& git -C $RepoRoot rev-parse --short $t).Trim()
            $tagDate = (& git -C $RepoRoot log -1 --format="%cd" --date=short $t).Trim()
            Write-Host "  Tag: $t (Commit: $tagCommit, Date: $tagDate)"
        }
    }
    return 0
}

# =========================================================================
# INTERACTIVE MENU
# =========================================================================
function Show-ReleaseMenu {
    while ($true) {
        Clear-Host
        Write-Host "========================================================================" -ForegroundColor Cyan
        Write-Host "           THQ BUSINESS - ONE-CLICK RELEASE AUTOMATION LAUNCHER         " -ForegroundColor Cyan
        Write-Host "========================================================================" -ForegroundColor Cyan
        Write-Host " Repository Root: $RepoRoot" -ForegroundColor DarkGray
        Write-Host " Target Device:   $QA_DEVICE_NAME ($QA_DEVICE_UUID)" -ForegroundColor DarkGray
        Write-Host " Channel:         internal_test" -ForegroundColor DarkGray
        Write-Host "========================================================================" -ForegroundColor Cyan
        Write-Host "  [1] Build THQ Business Installer Locally (BuildOnly)"
        Write-Host "  [2] Check Next Release Version and Configuration (CheckRelease)"
        Write-Host "  [3] Publish QA Update (PublishQA)"
        Write-Host "  [4] View Latest Release / Workflow Result (ViewLatest)"
        Write-Host "  [5] Exit"
        Write-Host "========================================================================" -ForegroundColor Cyan
        $choice = Read-Host "Select an option (1-5)"

        switch ($choice.Trim()) {
            "1" {
                try {
                    $localVer = Read-LocalVersionInfo
                    $latestTag = (& git -C $RepoRoot tag -l "v*" | Sort-Object | Select-Object -Last 1)
                    if ($latestTag -and $latestTag -notmatch "v$($localVer.Version)\+$($localVer.BuildNumber)") {
                        Write-Host ""
                        Write-Host "Notice: Local workspace version ($($localVer.Version)+$($localVer.BuildNumber)) diverges from latest release tag ($latestTag)." -ForegroundColor Yellow
                        $prompt = Read-Host "Do you want to compile local workspace source deliberately with -AllowDivergentBuild? (y/N)"
                        if ($prompt.Trim().ToLower() -eq "y" -or $prompt.Trim().ToLower() -eq "yes") {
                            Invoke-BuildOnly -AllowDivergentBuild
                        } else {
                            Write-Host "Build cancelled by user." -ForegroundColor Yellow
                        }
                    } else {
                        Invoke-BuildOnly
                    }
                } catch { Write-Host "Error: $_" -ForegroundColor Red }
                Write-Host "`nPress Enter to return to menu..."; [void][System.Console]::ReadLine()
            }
            "2" {
                try { Invoke-CheckRelease } catch { Write-Host "Error: $_" -ForegroundColor Red }
                Write-Host "`nPress Enter to return to menu..."; [void][System.Console]::ReadLine()
            }
            "3" {
                try { Invoke-PublishQA } catch { Write-Host "Error: $_" -ForegroundColor Red }
                Write-Host "`nPress Enter to return to menu..."; [void][System.Console]::ReadLine()
            }
            "4" {
                try { Invoke-ViewLatest } catch { Write-Host "Error: $_" -ForegroundColor Red }
                Write-Host "`nPress Enter to return to menu..."; [void][System.Console]::ReadLine()
            }
            "5" {
                Write-Host "Exiting launcher."
                return 0
            }
            default {
                Write-Host "Invalid choice. Please select 1, 2, 3, 4, or 5." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Entrypoint dispatcher
switch ($Mode) {
    "BuildOnly"    { exit (Invoke-BuildOnly) }
    "CheckRelease" { exit (Invoke-CheckRelease) }
    "PublishQA"    { exit (Invoke-PublishQA) }
    "ViewLatest"   { exit (Invoke-ViewLatest) }
    "Menu"         { exit (Show-ReleaseMenu) }
    default        { exit (Show-ReleaseMenu) }
}
