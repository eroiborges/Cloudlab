#Requires -Version 5.1
<#
.SYNOPSIS
    Installs certcollect.ps1 as a Windows Scheduled Task on the local machine.

.DESCRIPTION
    Performs the full on-VM setup for Certificate Health Monitoring:
      1. Creates C:\WindowsAzure\Certs\scripts (for the PS1 file) and
         C:\WindowsAzure\Certs\logs (for CertHealth.log / CertMetricLog.csv).
      2. Copies certcollect.ps1 to the install path on the VM.
      3. Registers the Windows Application Event Log source (ADMonitoringScript).
      4. Creates a Task Scheduler job that runs certcollect.ps1 every 15 minutes
         as the SYSTEM account with all sources enabled and DCR upload mode.

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
    DCR     – write CertMetricLog.csv for AMA pickup (default).
    Metrics – push directly to Azure Monitor Metrics REST API via Managed Identity.

.PARAMETER TaskName
    Name of the Scheduled Task. Default: CertMonitor-CertCollect

.PARAMETER IntervalMinutes
    How often certcollect.ps1 runs (minutes). Default: 1440 (24 hours)

.PARAMETER Force
    Overwrite the Scheduled Task if it already exists.

.EXAMPLE
    # Run from the scripts/ folder — deploys and schedules with all defaults
    .\Install-CertMonitor.ps1

.EXAMPLE
    # Use Metrics upload mode (requires Managed Identity on the VM)
    .\Install-CertMonitor.ps1 -UploadMode Metrics

.EXAMPLE
    # Override the source script path (e.g. deploying from a network share)
    .\Install-CertMonitor.ps1 -ScriptSourcePath '\\fileserver\deploy\certcollect.ps1'

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
    # RunAsPassword is omitted, the script will prompt interactively.
    # Not required when RunAsUser ends with '$' (Group Managed Service Account).
    [Parameter()]
    [System.Security.SecureString]$RunAsPassword
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

Write-Host "=== CertMonitor Install ===" -ForegroundColor Cyan
Write-Host "Script source  : $ScriptSourcePath"
Write-Host "Install path   : $ScriptInstallPath"
Write-Host "Monitoring dir : $MonitoringFolder"
Write-Host "Upload mode    : $UploadMode"
Write-Host "Task name      : $TaskName"
Write-Host "Interval       : every $IntervalMinutes minutes"
Write-Host ''

# ---------------------------------------------------------------------------
# Step 1: Create scripts and logs directories
# ---------------------------------------------------------------------------
$scriptsDir = Split-Path $ScriptInstallPath -Parent

if ($PSCmdlet.ShouldProcess("$scriptsDir; $MonitoringFolder", 'Create directories')) {
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
# All sources run by default (-Source is omitted → runs all).
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

if ($useSystem) {
    $principal = New-ScheduledTaskPrincipal `
                     -UserId    'SYSTEM' `
                     -LogonType ServiceAccount `
                     -RunLevel  Highest
    $plainPassword = $null
} else {
    $logonType = if ($isGmsa) { 'Password' } else { 'Password' }
    $principal = New-ScheduledTaskPrincipal `
                     -UserId    $RunAsUser `
                     -LogonType $logonType `
                     -RunLevel  Limited   # least-privilege account: no UAC elevation needed
    if ($isGmsa) {
        $plainPassword = $null   # gMSA: Task Scheduler manages the password
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
            # different parameter sets — use User + Password + RunLevel (no Principal).
            $regParams['User']     = $RunAsUser
            $regParams['Password'] = $plainPassword
            $regParams['RunLevel'] = 'Limited'  # least-privilege account: no UAC elevation needed
        } else {
            # SYSTEM or gMSA: Principal already carries UserId, LogonType, and RunLevel.
            $regParams['Principal'] = $principal
        }
        Register-ScheduledTask @regParams | Out-Null
        Write-Host "[4/4] Scheduled Task registered: $TaskName" -ForegroundColor Green

        # Trigger first run immediately so data appears without waiting for the repeat interval
        Write-Host "[4/4] Starting first run now..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "[4/4] First run started. Check $MonitoringFolder\CertHealth.log in a few seconds." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
$runAsDisplay = if ($useSystem) { 'SYSTEM' } else { $RunAsUser }
Write-Host '=== Installation complete ===' -ForegroundColor Cyan
Write-Host "Scheduled Task '$TaskName' will run certcollect.ps1 every $IntervalMinutes minutes as $runAsDisplay."
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Verify Azure Monitor Agent is installed on this VM.'
Write-Host '  2. Confirm the DCR is associated with this VM (Azure Portal -> Monitor -> DCR -> Resources).'
Write-Host '  3. Wait up to 15 minutes for first data to appear in Log Analytics:'
Write-Host "       CertHealth_CL | order by TimeGenerated desc | take 50"
Write-Host '  4. Run log rotation daily: scripts\Invoke-CertMonitorLogRotation.ps1'
