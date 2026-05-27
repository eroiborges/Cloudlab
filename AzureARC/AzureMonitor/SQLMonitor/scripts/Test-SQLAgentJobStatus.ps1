#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors SQL Server Agent job last-run status and duration.
    Logs results to the Windows Application Event Log for ingestion by Azure Monitor Agent.

.DESCRIPTION
    Replicates SCOM monitors:
      - "Last Run Status" (Warning severity, Agent Job object)
    Connects to SQL Server, queries msdb job history, and emits a structured
    key=value log line per job.

.PARAMETER InstanceName
    SQL Server instance name for connection (e.g. "localhost" or "localhost\SQL2019").
    Defaults to the local default instance.

.PARAMETER AgentInstanceName
    SCOM-style instance label written to the log (e.g. "MSSQLSERVER").

.PARAMETER FailedJobDurationWarningMinutes
    Emit a duration warning if any job ran longer than this threshold (minutes).
    Corresponds to SCOM monitor: SQL Server Agent Job Duration.

.PARAMETER LogDirectory
    Directory where the output log file is written. Default: C:\SQLMonitoring\Logs

.EXAMPLE
    .\Test-SQLAgentJobStatus.ps1 -InstanceName "localhost" -AgentInstanceName "MSSQLSERVER"

.NOTES
    Run as a Scheduled Task every 5 minutes with a SQL login that has VIEW SERVER STATE
    and access to msdb.dbo.sysjobhistory.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$InstanceName = 'localhost',

    [Parameter()]
    [string]$AgentInstanceName = 'MSSQLSERVER',

    [Parameter()]
    [int]$FailedJobDurationWarningMinutes = 120,

    [Parameter()]
    [string]$LogDirectory = 'C:\SQLMonitoring\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'Test-SQLAgentJobStatus'
$EVENT_SOURCE  = 'ADMonitoringScript'
$EVENT_LOG     = 'Application'
$LOG_FILE      = Join-Path $LogDirectory 'AgentJobStatus.log'
$TIMESTAMP_FMT = 'yyyy-MM-dd HH:mm:ss'

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
        [int]$EventId = 2000
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

function Emit-JobResult {
    param(
        [string]$JobName,
        [string]$Status,        # Succeeded | Failed | Cancelled | Running | Unknown | NeverRun
        [string]$Severity,      # OK | Warning | Error
        [string]$CheckResult,   # JobOK | JobFailed | JobNeverRun | DurationExceeded
        [double]$DurationMin,
        [string]$Message
    )
    $safeName    = $JobName    -replace ',', ';'
    $safeMessage = $Message    -replace ',', ';'
    $line = ("ScriptName={0},InstanceName={1},JobName={2},Status={3}," +
             "Severity={4},CheckResult={5},MetricValue={6},Message={7}") -f
             $SCRIPT_NAME, $AgentInstanceName, $safeName, $Status,
             $Severity, $CheckResult, [math]::Round($DurationMin, 2), $safeMessage

    Write-LogEntry -Line $line

    $eventType = switch ($Severity) {
        'Error'   { 'Error' }
        'Warning' { 'Warning' }
        default   { 'Information' }
    }
    $eventId = switch ($Severity) {
        'Error'   { 2002 }
        'Warning' { 2001 }
        default   { 2000 }
    }
    Write-EventEntry -Message $line -EntryType $eventType -EventId $eventId
}

function Invoke-SqlQuery {
    param(
        [string]$Server,
        [string]$Database,
        [string]$Query
    )
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=30;"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText  = $Query
        $command.CommandTimeout = 60
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataset)
        return $dataset.Tables[0]
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# ---------------------------------------------------------------------------
# SQL Query – Latest run per job
# ---------------------------------------------------------------------------
$query = @"
SELECT
    j.name                                                      AS JobName,
    j.enabled                                                   AS IsEnabled,
    h.run_status                                                AS RunStatus,
    -- Convert YYYYMMDD + HHMMSS to datetime
    msdb.dbo.agent_datetime(h.run_date, h.run_time)            AS LastRunTime,
    -- Duration in minutes: stored as HHMMSS integer
    (  (h.run_duration / 10000) * 60
     + ((h.run_duration % 10000) / 100)
     + (h.run_duration % 100) / 60.0 )                         AS DurationMinutes,
    h.message                                                   AS LastMessage
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id,
           run_date, run_time, run_status, run_duration, message,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0  -- Job outcome step only
) h ON h.job_id = j.job_id AND h.rn = 1
WHERE j.enabled = 1
ORDER BY j.name;
"@

# ---------------------------------------------------------------------------
# Main Logic
# ---------------------------------------------------------------------------

try {
    Ensure-EventSource
} catch {
    Write-Warning "Cannot register Event Source (may need elevation): $_"
}

try {
    $results = Invoke-SqlQuery -Server $InstanceName -Database 'msdb' -Query $query
} catch {
    $errMsg = "Failed to query SQL Server '$InstanceName' for agent job status: $($_.Exception.Message)"
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "Status=Unknown,Severity=Error,Message=$($errMsg -replace ',',';')")
    Write-EventEntry -Message $errMsg -EntryType 'Error' -EventId 2099
    exit 1
}

# run_status codes: 0=Failed, 1=Succeeded, 2=Retry, 3=Cancelled, 4=In Progress, NULL=Never run
$statusMap = @{
    0 = 'Failed'
    1 = 'Succeeded'
    2 = 'Retry'
    3 = 'Cancelled'
    4 = 'Running'
}

foreach ($row in $results) {
    $jobName     = [string]$row.JobName
    $runStatus   = if ($row.RunStatus -is [DBNull]) { $null } else { [int]$row.RunStatus }
    $durationMin = if ($row.DurationMinutes -is [DBNull]) { 0.0 } else { [double]$row.DurationMinutes }
    $lastMessage = if ($row.LastMessage -is [DBNull]) { '' } else { [string]$row.LastMessage }

    if ($null -eq $runStatus) {
        # Job has never run
        Emit-JobResult -JobName $jobName -Status 'NeverRun' -Severity 'Warning' `
            -CheckResult 'JobNeverRun' -DurationMin 0 `
            -Message "Job '$jobName' has never executed."
        continue
    }

    $statusText = $statusMap[$runStatus]
    if (-not $statusText) { $statusText = 'Unknown' }

    switch ($runStatus) {
        0 {
            # Failed – maps to SCOM Warning (Last Run Status monitor)
            Emit-JobResult -JobName $jobName -Status 'Failed' -Severity 'Warning' `
                -CheckResult 'JobFailed' -DurationMin $durationMin `
                -Message "Job '$jobName' FAILED. Duration: $([math]::Round($durationMin,1)) min. SQL msg: $lastMessage"
        }
        1 {
            # Succeeded – check duration threshold
            if ($durationMin -gt $FailedJobDurationWarningMinutes) {
                Emit-JobResult -JobName $jobName -Status 'Succeeded' -Severity 'Warning' `
                    -CheckResult 'DurationExceeded' -DurationMin $durationMin `
                    -Message "Job '$jobName' succeeded but exceeded duration threshold ($($FailedJobDurationWarningMinutes) min). Actual: $([math]::Round($durationMin,1)) min."
            } else {
                Emit-JobResult -JobName $jobName -Status 'Succeeded' -Severity 'OK' `
                    -CheckResult 'JobOK' -DurationMin $durationMin `
                    -Message "Job '$jobName' succeeded. Duration: $([math]::Round($durationMin,1)) min."
            }
        }
        default {
            Emit-JobResult -JobName $jobName -Status $statusText -Severity 'Warning' `
                -CheckResult "JobStatus_$statusText" -DurationMin $durationMin `
                -Message "Job '$jobName' status: $statusText. Duration: $([math]::Round($durationMin,1)) min."
        }
    }
}
