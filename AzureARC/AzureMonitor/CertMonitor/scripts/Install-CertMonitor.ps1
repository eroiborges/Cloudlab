#Requires -Version 5.1
<#
.SYNOPSIS
    Installs certcollect.ps1 (and optionally log rotation) as Windows Scheduled Tasks.

.DESCRIPTION
    Performs the full on-VM setup for Certificate Health Monitoring:
      1. Creates C:\WindowsAzure\Certs\scripts and C:\WindowsAzure\Certs\logs.
      2. Copies certcollect.ps1 to the install path on the VM.
      3. Registers the Windows Application Event Log source (ADMonitoringScript).
      4. Creates a Scheduled Task that runs certcollect.ps1 on the configured interval.
      5. (If -LogRotation $true) Copies Invoke-CertMonitorLogRotation.ps1 to the scripts folder.
      6. (If -LogRotation $true) Creates a daily 02:00 AM Scheduled Task for log rotation,
         using the same identity as the collector task - password prompted only once.

    Run once per VM after deploying the Azure infrastructure with main.bicep
    and after installing Azure Monitor Agent on the VM.

.PARAMETER ScriptSourcePath
    Path to certcollect.ps1 (the file to deploy). Resolved relative to this
    script's directory if not absolute.
    Default: .\certcollect.ps1 (sibling file in the scripts/ folder)

.PARAMETER ScriptInstallPath
    Destination path for certcollect.ps1 on this VM.
    Default: C:\WindowsAzure\Certs\scripts\certcollect.ps1

.PARAMETER MonitoringFolder
    Directory where CertHealth.log and CertMetricLog.csv are written.
    Must match the DCR file pattern configured in modules/dcr.bicep.
    Default: C:\WindowsAzure\Certs\logs

.PARAMETER UploadMode
    DCR     - write CertMetricLog.csv for AMA pickup (default).
    Metrics - push directly to Azure Monitor Metrics REST API via Managed Identity.

.PARAMETER TaskName
    Name of the Scheduled Task. Default: CertMonitor-CertCollect

.PARAMETER IntervalMinutes
    How often certcollect.ps1 runs (minutes). Default: 1440 (24 hours)

.PARAMETER Force
    Overwrite the Scheduled Task if it already exists.

.PARAMETER LogRotation
    When $true (default), copies Invoke-CertMonitorLogRotation.ps1 to the scripts folder
    and registers a CertMonitor-LogRotation Scheduled Task that runs daily at 02:00.
    Uses the same service account and credentials as the collector task - no second prompt.
    Set to $false to skip log rotation setup.

.PARAMETER LogRotationSourcePath
    Path to Invoke-CertMonitorLogRotation.ps1. Defaults to the sibling file in scripts/.

.PARAMETER LogRotationTaskName
    Name of the log rotation Scheduled Task. Default: CertMonitor-LogRotation

.EXAMPLE
    # Run from the scripts/ folder - deploys and schedules with all defaults
    .\Install-CertMonitor.ps1

.EXAMPLE
    # Use Metrics upload mode (requires Managed Identity on the VM)
    .\Install-CertMonitor.ps1 -UploadMode Metrics

.EXAMPLE
    # Override the source script path (e.g. deploying from a network share)
    .\Install-CertMonitor.ps1 -ScriptSourcePath '\\fileserver\deploy\certcollect.ps1'

.EXAMPLE
    # Skip log rotation (manage it separately or not needed)
    .\Install-CertMonitor.ps1 -LogRotation $false

.EXAMPLE
    # Domain gMSA - password prompted once and reused for both tasks
    .\Install-CertMonitor.ps1 -RunAsUser 'DOMAIN\svc-certmonitor$'

.NOTES
    Requires local Administrator privileges (Task Scheduler and Event Log registration).
    Run AFTER:
      1. main.bicep deployed (workspace, DCR, alerts created)
      2. Azure Monitor Agent installed on this VM
      3. DCR associated with this VM
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
param (
    [Parameter()]
    [string]$ScriptSourcePath = '',

    [Parameter()]
    [string]$ScriptInstallPath = 'C:\WindowsAzure\Certs\scripts\certcollect.ps1',

    [Parameter()]
    [string]$MonitoringFolder = 'C:\WindowsAzure\Certs\logs',

    [Parameter()]
    [ValidateSet('DCR', 'Metrics')]
    [string]$UploadMode = 'DCR',

    [Parameter()]
    [string]$TaskName = 'CertMonitor-CertCollect',

    [Parameter()]
    [int]$IntervalMinutes = 1440,  # 24 hours

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$RunAsUser = '',

    # Password for the service account (SecureString). If RunAsUser is set but
    # RunAsPassword is omitted, the script will prompt interactively once and the
    # same credential is reused for the log rotation task - no second prompt.
    # Not required when RunAsUser ends with '$' (Group Managed Service Account).
    [Parameter()]
    [System.Security.SecureString]$RunAsPassword,

    # Register the companion CertMonitor-LogRotation Scheduled Task (daily at 02:00).
    # Uses the same identity as the collector task - password prompted only once.
    # Default: $true
    [Parameter()]
    [bool]$LogRotation = $true,

    # Path to Invoke-CertMonitorLogRotation.ps1. Defaults to sibling file in scripts/ folder.
    [Parameter()]
    [string]$LogRotationSourcePath = '',

    # Name for the log rotation Scheduled Task.
    [Parameter()]
    [string]$LogRotationTaskName = 'CertMonitor-LogRotation'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EVENT_SOURCE = 'ADMonitoringScript'
$EVENT_LOG    = 'Application'

# ---------------------------------------------------------------------------
# Resolve source script path (default: certcollect.ps1 next to this script)
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($ScriptSourcePath)) {
    $ScriptSourcePath = Join-Path $PSScriptRoot 'certcollect.ps1'
}

if (-not (Test-Path $ScriptSourcePath)) {
    Write-Error "certcollect.ps1 not found at: $ScriptSourcePath`nProvide -ScriptSourcePath or run from the scripts/ folder."
    exit 1
}

# Resolve log rotation script path; disable gracefully if not found
if ($LogRotation) {
    if ([string]::IsNullOrEmpty($LogRotationSourcePath)) {
        $LogRotationSourcePath = Join-Path $PSScriptRoot 'Invoke-CertMonitorLogRotation.ps1'
    }
    if (-not (Test-Path $LogRotationSourcePath)) {
        Write-Warning "Invoke-CertMonitorLogRotation.ps1 not found at '$LogRotationSourcePath' - log rotation disabled."
        $LogRotation = $false
    }
}

Write-Host "=== CertMonitor Install ===" -ForegroundColor Cyan
Write-Host "Script source  : $ScriptSourcePath"
Write-Host "Install path   : $ScriptInstallPath"
Write-Host "Monitoring dir : $MonitoringFolder"
Write-Host "Upload mode    : $UploadMode"
Write-Host "Task name      : $TaskName"
Write-Host "Interval       : every $IntervalMinutes minutes"
$logRotationSuffix = if ($LogRotation) { " ($LogRotationTaskName)" } else { '' }
Write-Host "Log rotation   : $LogRotation$logRotationSuffix"
Write-Host ''

# ---------------------------------------------------------------------------
# Step 1: Create scripts and logs directories
# ---------------------------------------------------------------------------
$scriptsDir = Split-Path $ScriptInstallPath -Parent

if ($PSCmdlet.ShouldProcess("$scriptsDir, $MonitoringFolder", 'Create directories')) {
    New-Item -ItemType Directory -Path $scriptsDir       -Force | Out-Null
    New-Item -ItemType Directory -Path $MonitoringFolder -Force | Out-Null
    Write-Host "[1/4] Directories created:" -ForegroundColor Green
    Write-Host "       Scripts : $scriptsDir"
    Write-Host "       Logs    : $MonitoringFolder"
}

# ---------------------------------------------------------------------------
# Step 2: Copy certcollect.ps1 to scripts directory
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($ScriptInstallPath, 'Copy certcollect.ps1')) {
    Copy-Item -Path $ScriptSourcePath -Destination $ScriptInstallPath -Force
    Write-Host "[2/4] Copied certcollect.ps1 to: $ScriptInstallPath" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 3: Register Event Log source
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($EVENT_SOURCE, 'Register Event Log source')) {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EVENT_SOURCE, $EVENT_LOG)
            Write-Host "[3/4] Registered Event Log source: $EVENT_SOURCE" -ForegroundColor Green
        } else {
            Write-Host "[3/4] Event Log source already registered: $EVENT_SOURCE"
        }
    } catch {
        Write-Warning "[3/4] Could not register Event Log source (may need elevation or already registered under a different log): $_"
    }
}

# ---------------------------------------------------------------------------
# Step 4: Create / replace Scheduled Task
# ---------------------------------------------------------------------------
# Build the PowerShell arguments passed to certcollect.ps1.
# All sources run by default (-Source is omitted and all sources run).
# -MonitoringFolder and -UploadMode are always explicit for clarity.
$scriptArgs = "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$ScriptInstallPath`" " +
              "-MonitoringFolder `"$MonitoringFolder`" -UploadMode $UploadMode"

$action  = New-ScheduledTaskAction `
               -Execute 'powershell.exe' `
               -Argument $scriptArgs

$trigger = New-ScheduledTaskTrigger `
               -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
               -Once `
               -At (Get-Date).Date  # start of today; repetition handles recurrence

$settings = New-ScheduledTaskSettingsSet `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
                -MultipleInstances IgnoreNew `
                -StartWhenAvailable

# Determine run-as identity
$useSystem = [string]::IsNullOrEmpty($RunAsUser)
$isGmsa    = (-not $useSystem) -and $RunAsUser.TrimEnd().EndsWith('$')

# Initialize variables for StrictMode and for reuse in log rotation task registration.
$principal     = $null
$plainPassword = $null

if ($useSystem) {
    $principal = New-ScheduledTaskPrincipal `
                     -UserId    'SYSTEM' `
                     -LogonType ServiceAccount `
                     -RunLevel  Highest
} else {
    $principal = New-ScheduledTaskPrincipal `
                     -UserId    $RunAsUser `
                     -LogonType Password `
                     -RunLevel  Limited   # least-privilege account: no UAC elevation needed
    if ($isGmsa) {
        # gMSA: Task Scheduler manages the password
    } else {
        if (-not $RunAsPassword) {
            $RunAsPassword = Read-Host -AsSecureString "Password for '$RunAsUser'"
        }
        $bstr          = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($RunAsPassword)
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if ($PSCmdlet.ShouldProcess($TaskName, 'Register Scheduled Task')) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        Write-Warning "[4/4] Scheduled Task '$TaskName' already exists. Use -Force to overwrite."
    } else {
        if ($existing) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }

        $regParams = @{
            TaskName    = $TaskName
            Description = "Certificate Health Monitoring - runs certcollect.ps1 every $IntervalMinutes minutes."
            Action      = $action
            Trigger     = $trigger
            Settings    = $settings
        }

        if (-not $useSystem -and -not $isGmsa -and $plainPassword) {
            # Named account: Register-ScheduledTask -Principal and -User/-Password are in
            # different parameter sets - use User + Password + RunLevel (no Principal).
            $regParams['User']     = $RunAsUser
            $regParams['Password'] = $plainPassword
            $regParams['RunLevel'] = 'Limited'  # least-privilege account: no UAC elevation needed
        } else {
            # SYSTEM or gMSA: Principal already carries UserId, LogonType, and RunLevel.
            if (-not $principal) {
                throw "Run-as principal was not initialized. Check -RunAsUser and account settings."
            }
            $regParams['Principal'] = $principal
        }

        Register-ScheduledTask @regParams | Out-Null
        Write-Host "[4/4] Scheduled Task registered: $TaskName" -ForegroundColor Green

        # Trigger first run immediately so data appears without waiting for the repeat interval.
        Write-Host "[4/4] Starting first run now..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "[4/4] First run started. Check $MonitoringFolder\CertHealth.log in a few seconds." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Steps 5-6: Log rotation (conditional on -LogRotation $true)
# ---------------------------------------------------------------------------
if ($LogRotation) {
    $logRotInstallPath = Join-Path $scriptsDir 'Invoke-CertMonitorLogRotation.ps1'

    # Step 5: Copy log rotation script
    if ($PSCmdlet.ShouldProcess($logRotInstallPath, 'Copy Invoke-CertMonitorLogRotation.ps1')) {
        Copy-Item -Path $LogRotationSourcePath -Destination $logRotInstallPath -Force
        Write-Host "[5] Copied Invoke-CertMonitorLogRotation.ps1 to: $logRotInstallPath" -ForegroundColor Green
    }

    # Step 6: Register log rotation task - reuses $principal / $plainPassword, no second prompt
    $logRotAction   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                          -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$logRotInstallPath`""
    $logRotTrigger  = New-ScheduledTaskTrigger -Daily -At '02:00'
    $logRotSettings = New-ScheduledTaskSettingsSet `
                          -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
                          -StartWhenAvailable

    if ($PSCmdlet.ShouldProcess($LogRotationTaskName, 'Register log rotation Scheduled Task')) {
        $existingRot = Get-ScheduledTask -TaskName $LogRotationTaskName -ErrorAction SilentlyContinue
        if ($existingRot -and -not $Force) {
            Write-Warning "[6] Scheduled Task '$LogRotationTaskName' already exists. Use -Force to overwrite."
        } else {
            if ($existingRot) { Unregister-ScheduledTask -TaskName $LogRotationTaskName -Confirm:$false }
            $logRotParams = @{
                TaskName    = $LogRotationTaskName
                Description = 'CertMonitor log rotation - rotates and purges old log files daily at 02:00.'
                Action      = $logRotAction
                Trigger     = $logRotTrigger
                Settings    = $logRotSettings
            }
            if (-not $useSystem -and -not $isGmsa -and $plainPassword) {
                $logRotParams['User']     = $RunAsUser
                $logRotParams['Password'] = $plainPassword
                $logRotParams['RunLevel'] = 'Limited'
            } else {
                if (-not $principal) {
                    throw "Run-as principal was not initialized for log rotation task."
                }
                $logRotParams['Principal'] = $principal
            }
            Register-ScheduledTask @logRotParams | Out-Null
            Write-Host "[6] Scheduled Task registered: $LogRotationTaskName" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
$runAsDisplay = if ($useSystem) { 'SYSTEM' } else { $RunAsUser }
Write-Host '=== Installation complete ===' -ForegroundColor Cyan
Write-Host "Scheduled Task '$TaskName' will run certcollect.ps1 every $IntervalMinutes minutes as $runAsDisplay."
if ($LogRotation) {
    Write-Host "Scheduled Task '$LogRotationTaskName' will rotate logs daily at 02:00 as $runAsDisplay."
}
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Verify Azure Monitor Agent is installed on this VM.'
Write-Host '  2. Confirm the DCR is associated with this VM (Azure Portal -> Monitor -> DCR -> Resources).'
Write-Host '  3. Wait up to 15 minutes for first data to appear in Log Analytics:'
Write-Host "       CertHealth_CL | order by TimeGenerated desc | take 50"
if (-not $LogRotation) {
    Write-Host '  4. Set up log rotation manually: scripts\Invoke-CertMonitorLogRotation.ps1'
}
