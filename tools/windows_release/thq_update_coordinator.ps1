<#
.SYNOPSIS
    THQ ERP Windows Update Coordinator V2
    Coordinates detached installation, safety checks, pre-update backup,
    Inno Setup execution, verification, and failure recovery.
#>
param(
    [Parameter(Mandatory=$true)]
    [int]$ParentProcessId,

    [Parameter(Mandatory=$true)]
    [string]$InstallerPath,

    [Parameter(Mandatory=$true)]
    [string]$AppExePath,

    [Parameter(Mandatory=$true)]
    [string]$SessionFile,

    [switch]$Silent
)

$ErrorActionPreference = "Continue"

function Write-CoordinatorLog {
    param([string]$Message)
    try {
        $logDir = Split-Path -Parent $SessionFile
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        $logPath = Join-Path $logDir "thq_updater_coordinator.log"
        $line = "[$(Get-Date -Format o)] $Message"
        Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
    } catch {}
}

function Set-SessionProperty {
    param($Object, [string]$Name, $Value)
    if (-not $Object) { return }
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Save-SessionData {
    param($Object, [string]$Path)
    if (-not $Object -or -not (Test-Path $Path)) { return }
    try {
        $Object | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8
    } catch {
        Write-CoordinatorLog "Warning: Could not save session JSON: $_"
    }
}

function Send-TelemetryEvent {
    param(
        [string]$Status,
        [string]$ErrorMessage,
        [hashtable]$Metadata
    )
    if (-not $sessionData) { return }
    try {
        $headers = @{
            "apikey" = "sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ"
            "Authorization" = "Bearer sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ"
            "Content-Type" = "application/json"
        }
        $appKey = if ($sessionData.app_key) { $sessionData.app_key } else { "client" }
        $fromVer = if ($sessionData.from_version) { $sessionData.from_version } else { "8.1.0" }
        $fromBld = if ($sessionData.from_build) { [int]$sessionData.from_build } else { 16 }
        $toVer = if ($sessionData.target_version) { $sessionData.target_version } else { "8.2.0" }
        $toBld = if ($sessionData.target_build) { [int]$sessionData.target_build } else { 17 }

        $details = @{
            "attempt_id" = $sessionData.attempt_id
            "timestamp" = (Get-Date).ToUniversalTime().ToString("o")
        }
        if ($Metadata) {
            foreach ($k in $Metadata.Keys) {
                $details[$k] = $Metadata[$k]
            }
        }

        $body = @{
            "p_app_key" = $appKey
            "p_platform" = "windows"
            "p_device_id" = $sessionData.device_id
            "p_tenant_id" = $sessionData.tenant_id
            "p_from_version" = $fromVer
            "p_from_build" = $fromBld
            "p_to_version" = $toVer
            "p_to_build" = $toBld
            "p_status" = $Status.ToLowerInvariant()
            "p_error_message" = $ErrorMessage
            "p_details" = $details
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod -Uri "https://yguzrxcdvyimjrfvtcvp.supabase.co/rest/v1/rpc/app_update_log_record_v820" -Headers $headers -Method Post -Body $body -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
        Write-CoordinatorLog "Telemetry sent: $Status"
    } catch {
        Write-CoordinatorLog "Warning: Telemetry send failed ($Status): $_"
    }
}

Write-CoordinatorLog "=== THQ Windows Update Coordinator Started ==="
Write-CoordinatorLog "Parent PID: $ParentProcessId"
Write-CoordinatorLog "Installer: $InstallerPath"
Write-CoordinatorLog "AppExe: $AppExePath"
Write-CoordinatorLog "SessionFile: $SessionFile"
Write-CoordinatorLog "Silent: $Silent"

# -------------------------------------------------------------
# 1. Parameter and Security Validations (Issue 6 Hardening)
# -------------------------------------------------------------
if ($ParentProcessId -le 0) {
    Write-CoordinatorLog "Security Error: Invalid ParentProcessId: $ParentProcessId"
    exit 2
}

if (-not (Test-Path $SessionFile)) {
    Write-CoordinatorLog "Security Error: Session file does not exist: $SessionFile"
    exit 3
}

try {
    $AppExePath = (Resolve-Path $AppExePath -ErrorAction Stop).Path
    $appExeName = [System.IO.Path]::GetFileName($AppExePath).ToLowerInvariant()
    if ($appExeName -ne "thq_business.exe" -and $appExeName -ne "thq_pos.exe") {
        Write-CoordinatorLog "Security Error: AppExePath ($appExeName) is not a recognised THQ executable."
        exit 4
    }
} catch {
    Write-CoordinatorLog "Security Error: Unable to resolve AppExePath: $_"
    exit 4
}

try {
    $InstallerPath = (Resolve-Path $InstallerPath -ErrorAction Stop).Path
    if (-not $InstallerPath.ToLowerInvariant().EndsWith(".exe")) {
        Write-CoordinatorLog "Security Error: InstallerPath must be an .exe: $InstallerPath"
        exit 5
    }
} catch {
    Write-CoordinatorLog "Security Error: Installer path could not be resolved: $_"
    exit 5
}

$appDir = Split-Path -Parent $AppExePath
$sessionDir = Split-Path -Parent $SessionFile

$sessionData = $null
try {
    $rawSession = Get-Content -Path $SessionFile -Raw -Encoding utf8
    $sessionData = $rawSession | ConvertFrom-Json
} catch {
    Write-CoordinatorLog "Warning: Could not parse session JSON: $_"
}

# -------------------------------------------------------------
# 2. Pre-installation Health Checks: Disk Space
# -------------------------------------------------------------
try {
    $driveLetter = [System.IO.Path]::GetPathRoot($AppExePath)
    $drive = Get-PSDrive ($driveLetter.TrimEnd(':\')) -ErrorAction SilentlyContinue
    if ($drive -and $drive.Free -lt 200MB) {
        $freeMb = [math]::Round($drive.Free / 1MB, 2)
        Write-CoordinatorLog "Pre-check Failure: Insufficient disk space on $driveLetter ($freeMb MB free, 200 MB required)."
        if ($sessionData) {
            Set-SessionProperty -Object $sessionData -Name "status" -Value "insufficient_disk_space"
            Set-SessionProperty -Object $sessionData -Name "error_message" -Value "Insufficient disk space ($freeMb MB available, 200 MB required)."
            Save-SessionData -Object $sessionData -Path $SessionFile
        }
        if (Test-Path $AppExePath) {
            Start-Process -FilePath $AppExePath
        }
        exit 6
    }
} catch {
    Write-CoordinatorLog "Warning: Could not check disk space: $_"
}

# -------------------------------------------------------------
# 3. Create Pre-Installation Backup for Recovery (Issue 3)
# -------------------------------------------------------------
$fromVer = if ($sessionData.from_version) { $sessionData.from_version } else { "current" }
$fromBld = if ($sessionData.from_build) { $sessionData.from_build } else { "0" }
$backupDir = Join-Path $sessionDir "backup_v${fromVer}_b${fromBld}"

Write-CoordinatorLog "Creating pre-update backup at: $backupDir"
try {
    if (Test-Path $backupDir) {
        Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Get-ChildItem -Path $appDir -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $backupDir -Force
    }

    if ($sessionData) {
        Set-SessionProperty -Object $sessionData -Name "backup_directory" -Value $backupDir
        Set-SessionProperty -Object $sessionData -Name "status" -Value "backed_up"
        Save-SessionData -Object $sessionData -Path $SessionFile
    }
    Write-CoordinatorLog "Backup created successfully."
} catch {
    Write-CoordinatorLog "Warning: Backup creation failed: $_"
}

# -------------------------------------------------------------
# 4. Wait for Parent Flutter Process to Terminate
# -------------------------------------------------------------
Write-CoordinatorLog "Waiting for parent PID $ParentProcessId to exit..."
if ($sessionData) {
    Set-SessionProperty -Object $sessionData -Name "status" -Value "waiting_for_shutdown"
    Save-SessionData -Object $sessionData -Path $SessionFile
}

$waitStart = [DateTime]::UtcNow
$processTerminated = $false

while (([DateTime]::UtcNow - $waitStart).TotalSeconds -lt 25) {
    $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if (-not $parent -or $parent.HasExited) {
        $processTerminated = $true
        break
    }
    Start-Sleep -Milliseconds 250
}

if (-not $processTerminated) {
    Write-CoordinatorLog "Parent PID $ParentProcessId did not exit cleanly within 25 seconds. Attempting graceful close."
    $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($parent) {
        $parent.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 3
        if (-not $parent.HasExited) {
            Write-CoordinatorLog "Force terminating parent process."
            Stop-Process -Id $ParentProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-Sleep -Milliseconds 600

# -------------------------------------------------------------
# 5. Launch Inno Setup Installer
# -------------------------------------------------------------
if ($sessionData) {
    Set-SessionProperty -Object $sessionData -Name "status" -Value "installing"
    Save-SessionData -Object $sessionData -Path $SessionFile
}

$innoLogPath = Join-Path (Split-Path -Parent $SessionFile) "inno_setup.log"
$argList = "/CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /NORESTART /SUPPRESSMSGBOXES /LOG=`"$innoLogPath`""
if ($appDir -and (Test-Path $appDir)) {
    $argList += " /DIR=`"$appDir`""
}
$argList += " /SILENT /SP-"

# Safety guard: ensure no lingering processes hold binary locks
Get-Process -Name "thq_business", "thq_pos" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Write-CoordinatorLog "Launching Inno Setup: $InstallerPath with arguments: $argList (Silent: $Silent)"

$exitCode = -1
try {
    # Attempt elevated execution first (standard for Inno Setup with PrivilegesRequired=admin in Program Files)
    Write-CoordinatorLog "Requesting elevation for installer execution..."
    Send-TelemetryEvent -Status "elevation_requested"
    $installerProc = Start-Process -FilePath $InstallerPath -ArgumentList $argList -Verb RunAs -PassThru -Wait
    $exitCode = $installerProc.ExitCode
    Write-CoordinatorLog "Installer process (elevated) terminated with exit code: $exitCode"
} catch {
    Write-CoordinatorLog "Elevated launch exception: $($_.Exception.Message)"
    if ($_.Exception.Message -match "cancel|denied") {
        $exitCode = 1223 # ERROR_CANCELLED by user at UAC
        Write-CoordinatorLog "Operator declined UAC elevation prompt."
        Send-TelemetryEvent -Status "elevation_denied" -ErrorMessage "Operator declined UAC elevation prompt."
    } else {
        try {
            Write-CoordinatorLog "Attempting direct launch fallback..."
            $installerProc = Start-Process -FilePath $InstallerPath -ArgumentList $argList -PassThru -Wait
            $exitCode = $installerProc.ExitCode
            Write-CoordinatorLog "Installer process (direct) terminated with exit code: $exitCode"
        } catch {
            $exitCode = -999
            Write-CoordinatorLog "Exception executing installer directly: $_"
        }
    }
}

# -------------------------------------------------------------
# 6. Evaluate Outcome and Handle Real Recovery / Rollback
# -------------------------------------------------------------
$newExeExists = Test-Path $AppExePath

if ($exitCode -eq 0 -and $newExeExists) {
    Write-CoordinatorLog "Update installation verified successful (Exit Code 0, executable verified)."
    if ($sessionData) {
        Set-SessionProperty -Object $sessionData -Name "status" -Value "installed"
        Set-SessionProperty -Object $sessionData -Name "installer_exit_code" -Value 0
        Set-SessionProperty -Object $sessionData -Name "completed_at" -Value (Get-Date -Format o)
        Save-SessionData -Object $sessionData -Path $SessionFile
    }

    Start-Sleep -Milliseconds 500
    Write-CoordinatorLog "Launching newly updated application: $AppExePath"
    Send-TelemetryEvent -Status "restart_started" -Metadata @{ "exit_code" = 0 }
    Start-Process -FilePath $AppExePath
} else {
    Write-CoordinatorLog "Installation failed (Exit Code: $exitCode, Exe Exists: $newExeExists). INITIATING SAFE RECOVERY..."
    Send-TelemetryEvent -Status "install_failed" -ErrorMessage "Update installer exited with code $exitCode." -Metadata @{ "exit_code" = $exitCode }
    
    $recovered = $false
    $appExeValid = $false
    if (Test-Path $AppExePath) {
        try {
            $ver = (Get-Item $AppExePath).VersionInfo
            if ($ver -and $ver.FileVersion) {
                $appExeValid = $true
            }
        } catch {}
    }

    # Only restore from backup if application binary is missing or was damaged
    if (-not $appExeValid -and (Test-Path $backupDir)) {
        try {
            Write-CoordinatorLog "Restoring original application binaries from backup: $backupDir -> $appDir"
            Send-TelemetryEvent -Status "rollback_started" -ErrorMessage "Application binary missing or invalid after installer failure. Initiating file recovery."
            Get-ChildItem -Path $backupDir -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $appDir -Force
            }
            if (Test-Path $AppExePath) {
                $recovered = $true
                Write-CoordinatorLog "Application binaries successfully restored from backup."
                Send-TelemetryEvent -Status "rollback_completed"
            } else {
                Send-TelemetryEvent -Status "rollback_failed" -ErrorMessage "Executable still missing after rollback attempt."
            }
        } catch {
            Write-CoordinatorLog "Error during rollback restoration: $_"
            Send-TelemetryEvent -Status "rollback_failed" -ErrorMessage "Error during rollback restoration: $_"
        }
    } else {
        if ($appExeValid) {
            $recovered = $true
            Write-CoordinatorLog "Original application executable is present and intact at: $AppExePath."
        }
    }

    if ($sessionData) {
        Set-SessionProperty -Object $sessionData -Name "installer_exit_code" -Value $exitCode
        Set-SessionProperty -Object $sessionData -Name "completed_at" -Value (Get-Date -Format o)
        $friendlyError = if ($exitCode -eq 1223) {
            "UAC elevation prompt was cancelled by operator."
        } elseif ($exitCode -eq 1) {
            "Installation was cancelled before completion."
        } else {
            "Update installer exited with code $exitCode."
        }

        if ($recovered) {
            Set-SessionProperty -Object $sessionData -Name "status" -Value "recovered"
            Set-SessionProperty -Object $sessionData -Name "recovery_action" -Value "original_preserved"
            Set-SessionProperty -Object $sessionData -Name "error_message" -Value $friendlyError
        } else {
            Set-SessionProperty -Object $sessionData -Name "status" -Value "recovery_failed"
            Set-SessionProperty -Object $sessionData -Name "recovery_action" -Value "manual_repair_required"
            Set-SessionProperty -Object $sessionData -Name "error_message" -Value "$friendlyError Automatic recovery could not restore files."
        }
        Save-SessionData -Object $sessionData -Path $SessionFile
    }

    if ($recovered -and (Test-Path $AppExePath)) {
        Write-CoordinatorLog "Recovery complete: Relaunching preserved application: $AppExePath"
        Send-TelemetryEvent -Status "restart_started" -Metadata @{ "recovery_action" = "original_preserved" }
        Start-Process -FilePath $AppExePath
    } else {
        Write-CoordinatorLog "Critical: Automatic recovery failed or executable missing. Manual repair required."
    }
}

Write-CoordinatorLog "=== THQ Windows Update Coordinator Finished ==="

