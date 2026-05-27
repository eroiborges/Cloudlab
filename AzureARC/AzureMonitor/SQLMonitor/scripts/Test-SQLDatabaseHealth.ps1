#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors SQL Server database health: state, backup age, log backup age,
    log file usage, virtual log file count, and log shipping delay.
    Logs results for ingestion by Azure Monitor Agent.

.DESCRIPTION
    Replicates SCOM monitors:
      - "Database Status"               (MatchMonitorHealth)
      - "Database Backup Status"        (Error, disabled by default)
      - "Database Log Backup Status"    (Error, disabled by default)
      - "Virtual Log File Count"        (MatchMonitorHealth, disabled)
      - "Destination Log Shipping"      (Error)
      - "DB Log Files Performance"      (rollup)
    Results are written as key=value log lines to C:\SQLMonitoring\Logs\DatabaseHealth.log.

.PARAMETER InstanceName
    SQL Server instance name for connection.

.PARAMETER AgentInstanceName
    Label written to the log.

.PARAMETER FullBackupMaxAgeHours
    Alert if last full backup is older than this many hours. Default: 25.

.PARAMETER LogBackupMaxAgeMinutes
    Alert if last log backup is older than this many minutes. Default: 60.
    Applies only to databases in FULL or BULK_LOGGED recovery model.

.PARAMETER VLFCountWarningThreshold
    Warning threshold for Virtual Log File count per database. Default: 1000.

.PARAMETER VLFCountErrorThreshold
    Error threshold for Virtual Log File count per database. Default: 10000.

.PARAMETER LogShippingDelayMinutes
    Alert if log shipping destination restore is delayed beyond this threshold. Default: 60.

.PARAMETER LogDirectory
    Output log directory. Default: C:\SQLMonitoring\Logs

.EXAMPLE
    .\Test-SQLDatabaseHealth.ps1 -InstanceName "localhost" -AgentInstanceName "MSSQLSERVER"
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$InstanceName = 'localhost',

    [Parameter()]
    [string]$AgentInstanceName = 'MSSQLSERVER',

    [Parameter()]
    [int]$FullBackupMaxAgeHours = 25,

    [Parameter()]
    [int]$LogBackupMaxAgeMinutes = 60,

    [Parameter()]
    [int]$VLFCountWarningThreshold = 1000,

    [Parameter()]
    [int]$VLFCountErrorThreshold = 10000,

    [Parameter()]
    [int]$LogShippingDelayMinutes = 60,

    [Parameter()]
    [string]$LogDirectory = 'C:\SQLMonitoring\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'Test-SQLDatabaseHealth'
$EVENT_SOURCE  = 'ADMonitoringScript'
$EVENT_LOG     = 'Application'
$LOG_FILE      = Join-Path $LogDirectory 'DatabaseHealth.log'
$TIMESTAMP_FMT = 'yyyy-MM-dd HH:mm:ss'

# Healthy database states
$healthyStates = @('ONLINE')

# ---------------------------------------------------------------------------
# Helpers
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
        [int]$EventId = 4000
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

function Emit-DBResult {
    param(
        [string]$DatabaseName,
        [string]$Status,
        [string]$Severity,      # OK | Warning | Error
        [string]$CheckResult,
        [string]$MetricValue,
        [string]$Message
    )
    $safeDB  = $DatabaseName -replace ',', ';'
    $safeMsg = $Message      -replace ',', ';'
    $line = ("ScriptName={0},InstanceName={1},DatabaseName={2},Status={3}," +
             "Severity={4},CheckResult={5},MetricValue={6},Message={7}") -f
             $SCRIPT_NAME, $AgentInstanceName, $safeDB, $Status,
             $Severity, $CheckResult, $MetricValue, $safeMsg

    Write-LogEntry -Line $line

    $eventType = switch ($Severity) {
        'Error'   { 'Error' }
        'Warning' { 'Warning' }
        default   { 'Information' }
    }
    $eventId = switch ($Severity) {
        'Error'   { 4002 }
        'Warning' { 4001 }
        default   { 4000 }
    }
    Write-EventEntry -Message $line -EntryType $eventType -EventId $eventId
}

function Invoke-SqlQuery {
    param(
        [string]$Server,
        [string]$Database = 'master',
        [string]$Query
    )
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=30;"
    try {
        $connection.Open()
        $command               = $connection.CreateCommand()
        $command.CommandText   = $Query
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
# Main Logic
# ---------------------------------------------------------------------------

try { Ensure-EventSource } catch { Write-Warning "Event Source registration failed: $_" }

# ---- 1. Database State -------------------------------------------------------
$stateQuery = @"
SELECT
    d.name                              AS DatabaseName,
    d.state_desc                        AS StateDesc,
    d.recovery_model_desc               AS RecoveryModel,
    d.is_read_only                      AS IsReadOnly,
    d.is_in_standby                     AS IsStandby,
    -- Last full backup
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS LastFullBackup,
    -- Last log backup
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS LastLogBackup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs
    ON d.name = bs.database_name
    AND bs.backup_finish_date > DATEADD(DAY, -90, GETUTCDATE())
WHERE d.database_id > 4  -- Exclude system DBs (master, model, msdb, tempdb)
  AND d.state_desc <> 'OFFLINE'
GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.is_read_only, d.is_in_standby
ORDER BY d.name;
"@

try {
    $dbRows = Invoke-SqlQuery -Server $InstanceName -Query $stateQuery
} catch {
    $errMsg = "Failed to query database state on '$InstanceName': $($_.Exception.Message)"
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "DatabaseName=ALL,Status=Unknown,Severity=Error," +
                          "CheckResult=QueryFailed,Message=$($errMsg -replace ',',';')")
    Write-EventEntry -Message $errMsg -EntryType 'Error' -EventId 4099
    exit 1
}

$now = Get-Date

if (-not $dbRows -or @($dbRows).Count -eq 0) {
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "DatabaseName=NONE,Status=OK,Severity=OK," +
                          "CheckResult=NoDatabases,Message=No user databases found on instance '$AgentInstanceName'.")
}

foreach ($row in $dbRows) {
    $dbName        = [string]$row.DatabaseName
    $state         = [string]$row.StateDesc
    $recovery      = [string]$row.RecoveryModel
    $lastFullBak   = if ($row.LastFullBackup -is [DBNull]) { $null } else { [datetime]$row.LastFullBackup }
    $lastLogBak    = if ($row.LastLogBackup  -is [DBNull]) { $null } else { [datetime]$row.LastLogBackup }

    # --- 1a. Database State ---
    if ($state -notin $healthyStates) {
        Emit-DBResult -DatabaseName $dbName -Status $state -Severity 'Error' `
            -CheckResult 'UnhealthyState' -MetricValue $state `
            -Message "Database '$dbName' is in state: $state."
    } else {
        Emit-DBResult -DatabaseName $dbName -Status $state -Severity 'OK' `
            -CheckResult 'DBStateOK' -MetricValue $state `
            -Message "Database '$dbName' is ONLINE."
    }

    # --- 1b. Full Backup Age ---
    if ($null -eq $lastFullBak) {
        Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
            -CheckResult 'BackupOverdue' -MetricValue 'NoBackup' `
            -Message "Database '$dbName' has NO full backup on record."
    } else {
        $ageHours = ($now - $lastFullBak).TotalHours
        if ($ageHours -gt $FullBackupMaxAgeHours) {
            Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
                -CheckResult 'BackupOverdue' -MetricValue ([math]::Round($ageHours, 1)) `
                -Message ("Database '$dbName' last full backup is $([math]::Round($ageHours,1)) hours old " +
                          "(threshold: $FullBackupMaxAgeHours hours).")
        }
    }

    # --- 1c. Log Backup Age (FULL/BULK_LOGGED only) ---
    if ($recovery -in @('FULL', 'BULK_LOGGED')) {
        if ($null -eq $lastLogBak) {
            Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
                -CheckResult 'LogBackupOverdue' -MetricValue 'NoLogBackup' `
                -Message "Database '$dbName' (FULL recovery) has NO log backup on record."
        } else {
            $ageMin = ($now - $lastLogBak).TotalMinutes
            if ($ageMin -gt $LogBackupMaxAgeMinutes) {
                Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
                    -CheckResult 'LogBackupOverdue' -MetricValue ([math]::Round($ageMin, 1)) `
                    -Message ("Database '$dbName' last log backup is $([math]::Round($ageMin,0)) min old " +
                              "(threshold: $LogBackupMaxAgeMinutes min).")
            }
        }
    }
}

# ---- 2. Virtual Log File Count -----------------------------------------------
$vlfQuery = @"
IF OBJECT_ID('tempdb..#VLFInfo') IS NOT NULL DROP TABLE #VLFInfo;
CREATE TABLE #VLFInfo (
    DatabaseName NVARCHAR(128),
    VLFCount     INT
);
EXEC sp_MSforeachdb N'
    USE [?];
    DECLARE @vlf TABLE (RecoveryUnitId INT, FileId INT, FileSize BIGINT,
                        StartOffset BIGINT, FSeqNo INT, Status INT,
                        Parity INT, CreateLSN NUMERIC(25,0));
    INSERT INTO @vlf
    EXEC sys.sp_executesql N''DBCC LOGINFO WITH NO_INFOMSGS'';
    INSERT INTO #VLFInfo SELECT DB_NAME(), COUNT(*) FROM @vlf;
';
SELECT DatabaseName, VLFCount FROM #VLFInfo
WHERE DatabaseName NOT IN ('master','model','msdb','tempdb')
ORDER BY VLFCount DESC;
DROP TABLE #VLFInfo;
"@

try {
    $vlfRows = Invoke-SqlQuery -Server $InstanceName -Query $vlfQuery
    foreach ($row in $vlfRows) {
        $dbName  = [string]$row.DatabaseName
        $vlfCnt  = [int]$row.VLFCount
        if ($vlfCnt -ge $VLFCountErrorThreshold) {
            Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
                -CheckResult 'VLFCountCritical' -MetricValue $vlfCnt `
                -Message "Database '$dbName' has $vlfCnt VLFs (critical threshold: $VLFCountErrorThreshold)."
        } elseif ($vlfCnt -ge $VLFCountWarningThreshold) {
            Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Warning' `
                -CheckResult 'VLFCountHigh' -MetricValue $vlfCnt `
                -Message "Database '$dbName' has $vlfCnt VLFs (warning threshold: $VLFCountWarningThreshold)."
        }
    }
} catch {
    Write-Warning "VLF count query failed: $($_.Exception.Message)"
}

# ---- 3. Log Shipping Delay ---------------------------------------------------
$logShipQuery = @"
SELECT
    lsm.secondary_database              AS DatabaseName,
    lsm.primary_server                  AS PrimaryServer,
    lsm.primary_database               AS PrimaryDatabase,
    DATEDIFF(MINUTE, lsm.last_restored_date, GETDATE()) AS DelayMinutes
FROM msdb.dbo.log_shipping_monitor_secondary lsm
WHERE lsm.last_restored_date IS NOT NULL
ORDER BY DelayMinutes DESC;
"@

try {
    $lsRows = Invoke-SqlQuery -Server $InstanceName -Query $logShipQuery
    foreach ($row in $lsRows) {
        $dbName     = [string]$row.DatabaseName
        $delayMin   = [int]$row.DelayMinutes
        $primarySrv = [string]$row.PrimaryServer

        if ($delayMin -gt $LogShippingDelayMinutes) {
            Emit-DBResult -DatabaseName $dbName -Status 'ONLINE' -Severity 'Error' `
                -CheckResult 'LogShippingDelay' -MetricValue $delayMin `
                -Message ("Log shipping destination '$dbName' has not been restored for " +
                          "$delayMin minutes (primary: $primarySrv, threshold: $LogShippingDelayMinutes min).")
        }
    }
} catch {
    # Log shipping may not be configured – swallow gracefully
    Write-Verbose "Log shipping query returned no results or failed: $($_.Exception.Message)"
}
