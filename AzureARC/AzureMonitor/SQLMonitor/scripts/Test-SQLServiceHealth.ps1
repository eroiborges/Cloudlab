#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors SQL Server Windows Service, SQL Agent Service, and SSIS Service health.
    Logs results to the Windows Application Event Log for ingestion by Azure Monitor Agent.

.DESCRIPTION
    Replicates SCOM monitors:
      - "SQL Server Windows Service"       (Error severity)
      - "SQL Server Agent Service"         (Error severity)
      - "Integration Service Health Status" (Error severity)
    Results are written as key=value pairs to C:\SQLMonitoring\Logs\ServiceHealth.log
    and to the Application Event Log (Source: ADMonitoringScript).

.PARAMETER InstanceName
    SQL Server instance name. Use MSSQLSERVER for the default instance,
    or MSSQL$INSTANCENAME for named instances.

.PARAMETER LogDirectory
    Directory where the output log file is written. Default: C:\SQLMonitoring\Logs

.EXAMPLE
    .\Test-SQLServiceHealth.ps1 -InstanceName "MSSQLSERVER"

.NOTES
    Run as a Scheduled Task on every SQL Server host every 5 minutes.
    Requires local Administrator privileges.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$InstanceName = 'MSSQLSERVER',

    [Parameter()]
    [string]$LogDirectory = 'C:\SQLMonitoring\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'Test-SQLServiceHealth'
$EVENT_SOURCE  = 'ADMonitoringScript'
$EVENT_LOG     = 'Application'
$LOG_FILE      = Join-Path $LogDirectory 'ServiceHealth.log'
$TIMESTAMP_FMT = 'yyyy-MM-dd HH:mm:ss'

# Map instance name to service names
if ($InstanceName -eq 'MSSQLSERVER') {
    $sqlServiceName   = 'MSSQLSERVER'
    $agentServiceName = 'SQLSERVERAGENT'
} else {
    # Named instance: MSSQL$INSTANCENAME / SQLAgent$INSTANCENAME
    $bare             = $InstanceName -replace '^MSSQL\$', ''
    $sqlServiceName   = "MSSQL`$$bare"
    $agentServiceName = "SQLAgent`$$bare"
}

# SSIS service names by version (check all present)
$ssisServiceNames = @(
    'MsDtsServer150',  # SQL 2019
    'MsDtsServer140',  # SQL 2017
    'MsDtsServer130',  # SQL 2016
    'MsDtsServer120',  # SQL 2014
    'MsDtsServer110'   # SQL 2012
)

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

function Ensure-EventSource {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
        [System.Diagnostics.EventLog]::CreateEventSource($EVENT_SOURCE, $EVENT_LOG)
    }
}

function Write-EventEntry {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = 'Information',
        [int]$EventId = 1000
    )
    try {
        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE `
            -EventId $EventId -EntryType $EntryType -Message $Message
    } catch {
        Write-Warning "Failed to write to Event Log: $_"
    }
}

function Write-LogEntry {
    param([string]$Line)
    try {
        if (-not (Test-Path $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        }
        $timestamp = (Get-Date).ToString($TIMESTAMP_FMT)
        "$timestamp $Line" | Out-File -FilePath $LOG_FILE -Append -Encoding utf8
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

function Emit-Result {
    param(
        [string]$ServiceCategory,  # SQLEngine | SQLAgent | SSIS
        [string]$ServiceName,
        [string]$Status,           # Running | Stopped | NotFound
        [string]$Severity,         # OK | Error
        [string]$Message
    )
    $line = ("ScriptName={0},InstanceName={1},ServiceCategory={2},ServiceName={3}," +
             "Status={4},Severity={5},Message={6}") -f
             $SCRIPT_NAME, $InstanceName, $ServiceCategory, $ServiceName,
             $Status, $Severity, ($Message -replace ',', ';')

    Write-LogEntry -Line $line

    $eventType = if ($Severity -eq 'Error') { 'Error' } else { 'Information' }
    $eventId   = if ($Severity -eq 'Error') { 1001 } else { 1000 }
    Write-EventEntry -Message $line -EntryType $eventType -EventId $eventId
}

# ---------------------------------------------------------------------------
# Main Logic
# ---------------------------------------------------------------------------

try {
    Ensure-EventSource
} catch {
    Write-Warning "Cannot register Event Source (may need elevation): $_"
}

# --- 1. SQL Server DB Engine Service ---
try {
    $svc = Get-Service -Name $sqlServiceName -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Emit-Result -ServiceCategory 'SQLEngine' -ServiceName $sqlServiceName `
            -Status 'Running' -Severity 'OK' `
            -Message "SQL Server service '$sqlServiceName' is running."
    } else {
        Emit-Result -ServiceCategory 'SQLEngine' -ServiceName $sqlServiceName `
            -Status $svc.Status.ToString() -Severity 'Error' `
            -Message "SQL Server service '$sqlServiceName' is NOT running. State: $($svc.Status)."
    }
} catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
    Emit-Result -ServiceCategory 'SQLEngine' -ServiceName $sqlServiceName `
        -Status 'NotFound' -Severity 'Error' `
        -Message "SQL Server service '$sqlServiceName' was not found on this host."
} catch {
    Emit-Result -ServiceCategory 'SQLEngine' -ServiceName $sqlServiceName `
        -Status 'Unknown' -Severity 'Error' `
        -Message "Error querying SQL Server service '$sqlServiceName': $($_.Exception.Message)"
}

# --- 2. SQL Server Agent Service ---
try {
    $agentSvc = Get-Service -Name $agentServiceName -ErrorAction Stop
    if ($agentSvc.Status -eq 'Running') {
        Emit-Result -ServiceCategory 'SQLAgent' -ServiceName $agentServiceName `
            -Status 'Running' -Severity 'OK' `
            -Message "SQL Agent service '$agentServiceName' is running."
    } else {
        Emit-Result -ServiceCategory 'SQLAgent' -ServiceName $agentServiceName `
            -Status $agentSvc.Status.ToString() -Severity 'Error' `
            -Message "SQL Agent service '$agentServiceName' is NOT running. State: $($agentSvc.Status)."
    }
} catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
    # SQL Express editions do not have SQL Agent – log as informational
    Emit-Result -ServiceCategory 'SQLAgent' -ServiceName $agentServiceName `
        -Status 'NotFound' -Severity 'OK' `
        -Message "SQL Agent service '$agentServiceName' not found (expected on Express editions)."
} catch {
    Emit-Result -ServiceCategory 'SQLAgent' -ServiceName $agentServiceName `
        -Status 'Unknown' -Severity 'Error' `
        -Message "Error querying SQL Agent service '$agentServiceName': $($_.Exception.Message)"
}

# --- 3. SSIS Services ---
$ssisFound = $false
foreach ($ssisSvcName in $ssisServiceNames) {
    try {
        $ssisSvc = Get-Service -Name $ssisSvcName -ErrorAction Stop
        $ssisFound = $true
        if ($ssisSvc.Status -eq 'Running') {
            Emit-Result -ServiceCategory 'SSIS' -ServiceName $ssisSvcName `
                -Status 'Running' -Severity 'OK' `
                -Message "SSIS service '$ssisSvcName' is running."
        } else {
            Emit-Result -ServiceCategory 'SSIS' -ServiceName $ssisSvcName `
                -Status $ssisSvc.Status.ToString() -Severity 'Error' `
                -Message "SSIS service '$ssisSvcName' is NOT running. State: $($ssisSvc.Status)."
        }
        break  # Only check the first SSIS version found
    } catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
        continue  # Try next version
    } catch {
        Emit-Result -ServiceCategory 'SSIS' -ServiceName $ssisSvcName `
            -Status 'Unknown' -Severity 'Error' `
            -Message "Error querying SSIS service '$ssisSvcName': $($_.Exception.Message)"
        break
    }
}
if (-not $ssisFound) {
    Emit-Result -ServiceCategory 'SSIS' -ServiceName 'MsDtsServer' `
        -Status 'NotInstalled' -Severity 'OK' `
        -Message 'SSIS is not installed on this host.'
}
