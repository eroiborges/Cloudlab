#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors SQL Server Availability Group replica synchronization state, roles,
    and automatic failover readiness.
    Logs results for ingestion by Azure Monitor Agent.

.DESCRIPTION
    Replicates SCOM monitors:
      - "Availability Database Data Synchronization" (MatchMonitorHealth)
      - "Availability Database Suspension State"     (MatchMonitorHealth)
      - "Availability Group Automatic Failover"      (Error rollup)
      - "Availability Replicas Connection (rollup)"  (Warning)
      - "Availability Replica Role Changed"          (Alert rule)
      - "Synchronous Replicas Data Synchronization"  (Warning rollup)
    Results are written as key=value log lines to C:\SQLMonitoring\Logs\AGStatus.log.

.PARAMETER InstanceName
    SQL Server instance name for connection (e.g. "localhost" or "localhost\SQL2019").

.PARAMETER AgentInstanceName
    Label written to the log (e.g. "MSSQLSERVER").

.PARAMETER LogDirectory
    Output log directory. Default: C:\SQLMonitoring\Logs

.EXAMPLE
    .\Test-SQLAvailabilityGroup.ps1 -InstanceName "localhost" -AgentInstanceName "MSSQLSERVER"

.NOTES
    Run as a Scheduled Task every 5 minutes. Requires VIEW SERVER STATE permission.
    Only meaningful on instances that participate in an Availability Group.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$InstanceName = 'localhost',

    [Parameter()]
    [string]$AgentInstanceName = 'MSSQLSERVER',

    [Parameter()]
    [string]$LogDirectory = 'C:\SQLMonitoring\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'Test-SQLAvailabilityGroup'
$EVENT_SOURCE  = 'ADMonitoringScript'
$EVENT_LOG     = 'Application'
$LOG_FILE      = Join-Path $LogDirectory 'AGStatus.log'
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
        [int]$EventId = 3000
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

function Emit-AGResult {
    param(
        [string]$AGName,
        [string]$DatabaseName,
        [string]$ReplicaServer,
        [string]$ReplicaRole,          # PRIMARY | SECONDARY | RESOLVING
        [string]$SyncState,            # SYNCHRONIZED | SYNCHRONIZING | NOT SYNCHRONIZING
        [string]$ConnState,            # CONNECTED | DISCONNECTED
        [string]$SuspendReason,        # NONE | USER_SUSPENDED | SUSPEND_FROM_PARTNER | ...
        [bool]  $IsDataMovementSuspended,
        [bool]  $IsFailoverReady,
        [string]$Status,
        [string]$Severity,             # OK | Warning | Error
        [string]$CheckResult,
        [string]$Message
    )
    $safeMsg = $Message -replace ',', ';'
    $line = ("ScriptName={0},InstanceName={1},AGName={2},DatabaseName={3}," +
             "ReplicaServer={4},ReplicaRole={5},Status={6},SyncState={7}," +
             "ConnState={8},DataMovementSuspended={9},IsFailoverReady={10}," +
             "Severity={11},CheckResult={12},Message={13}") -f
             $SCRIPT_NAME, $AgentInstanceName, $AGName, $DatabaseName,
             $ReplicaServer, $ReplicaRole, $Status, $SyncState,
             $ConnState, $IsDataMovementSuspended, $IsFailoverReady,
             $Severity, $CheckResult, $safeMsg

    Write-LogEntry -Line $line

    $eventType = switch ($Severity) {
        'Error'   { 'Error' }
        'Warning' { 'Warning' }
        default   { 'Information' }
    }
    $eventId = switch ($Severity) {
        'Error'   { 3002 }
        'Warning' { 3001 }
        default   { 3000 }
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
        $command.CommandText   = $Query
        $command.CommandTimeout = 60
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataset)
        # Write-Output -NoEnumerate prevents PowerShell from unrolling the DataTable
        # (DataTable implements IEnumerable, so a plain 'return' would yield DataRow objects
        #  instead of the DataTable itself, breaking .Rows access in callers).
        Write-Output -NoEnumerate $dataset.Tables[0]
    } finally {
        if ($connection.State -eq 'Open') { $connection.Close() }
    }
}

# ---------------------------------------------------------------------------
# SQL Query – AG replica and database state
# ---------------------------------------------------------------------------
$query = @"
SELECT
    ag.name                                     AS AGName,
    adr.replica_server_name                     AS ReplicaServer,
    ars.role_desc                               AS ReplicaRole,
    ars.connected_state_desc                    AS ConnectedState,
    ars.synchronization_health_desc             AS SyncHealth,
    adr.availability_mode                        AS AvailabilityMode,
    adr.failover_mode                            AS FailoverMode,
    adr.seeding_mode                             AS SeedingMode,
    ISNULL(DB_NAME(drs.database_id), '(AG Level)') AS DatabaseName,
    drs.synchronization_state_desc              AS SyncState,
    drs.is_suspended                            AS IsDataMovSuspended,
    drs.suspend_reason_desc                     AS SuspendReason,
    CASE
        WHEN adr.failover_mode_desc = 'AUTOMATIC'       -- use _desc; integer value varies by SQL Server version
             AND ars.role_desc = 'SECONDARY'
             AND ars.connected_state_desc = 'CONNECTED'
             AND drs.synchronization_state_desc = 'SYNCHRONIZED'
        THEN 1 ELSE 0
    END                                         AS IsFailoverReady
FROM sys.availability_groups ag
JOIN sys.availability_replicas adr
    ON ag.group_id = adr.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON adr.replica_id = ars.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states drs
    ON ars.replica_id = drs.replica_id
ORDER BY ag.name, adr.replica_server_name, DB_NAME(drs.database_id);
"@

# ---------------------------------------------------------------------------
# Main Logic
# ---------------------------------------------------------------------------

try { Ensure-EventSource } catch { Write-Warning "Event Source registration failed: $_" }

# Check if this instance participates in any AG
try {
    $hadrEnabled = Invoke-SqlQuery -Server $InstanceName -Database 'master' `
        -Query "SELECT SERVERPROPERTY('IsHadrEnabled') AS IsEnabled"
    if ([int]$hadrEnabled.Rows[0]['IsEnabled'] -ne 1) {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                              "Status=NA,Severity=OK,CheckResult=HADRNotEnabled," +
                              "Message=HADR not enabled on this instance")
        exit 0
    }
} catch {
    $errMsg = "Failed to query HADR status on '$InstanceName': $($_.Exception.Message)"
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "Status=Unknown,Severity=Error,CheckResult=QueryFailed," +
                          "Message=$($errMsg -replace ',',';')")
    Write-EventEntry -Message $errMsg -EntryType 'Error' -EventId 3099
    exit 1
}

try {
    $results = Invoke-SqlQuery -Server $InstanceName -Database 'master' -Query $query
} catch {
    $errMsg = "Failed to query AG state on '$InstanceName': $($_.Exception.Message)"
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "Status=Unknown,Severity=Error,CheckResult=QueryFailed," +
                          "Message=$($errMsg -replace ',',';')")
    Write-EventEntry -Message $errMsg -EntryType 'Error' -EventId 3099
    exit 1
}

if ($results.Rows.Count -eq 0) {
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName," +
                          "Status=NA,Severity=OK,CheckResult=NoAGFound," +
                          "Message=No Availability Groups found on this instance")
    exit 0
}

# Track per-AG failover readiness
$agFailoverReady = @{}

foreach ($row in $results) {
    $agName       = [string]$row.AGName
    $dbName       = [string]$row.DatabaseName
    $replica      = [string]$row.ReplicaServer
    $role         = [string]$row.ReplicaRole
    $connState    = [string]$row.ConnectedState
    $syncState    = if ($row.SyncState    -is [DBNull]) { 'N/A' } else { [string]$row.SyncState }
    $suspended    = if ($row.IsDataMovSuspended -is [DBNull]) { $false } else { [bool]$row.IsDataMovSuspended }
    $suspendWhy   = if ($row.SuspendReason -is [DBNull]) { 'NONE' } else { [string]$row.SuspendReason }
    $failoverReady= if ($row.IsFailoverReady -is [DBNull]) { $false } else { [bool]([int]$row.IsFailoverReady) }

    if ($failoverReady) { $agFailoverReady[$agName] = $true }
    if (-not $agFailoverReady.ContainsKey($agName)) { $agFailoverReady[$agName] = $false }

    # --- Check 1: Connection state ---
    if ($connState -ne 'CONNECTED' -and $role -ne 'PRIMARY') {
        Emit-AGResult -AGName $agName -DatabaseName $dbName -ReplicaServer $replica `
            -ReplicaRole $role -SyncState $syncState -ConnState $connState `
            -SuspendReason $suspendWhy -IsDataMovementSuspended $suspended `
            -IsFailoverReady $failoverReady -Status 'Disconnected' `
            -Severity 'Warning' -CheckResult 'Disconnected' `
            -Message "Replica '$replica' in AG '$agName' is DISCONNECTED."
        continue
    }

    # --- Check 2: Data movement suspended ---
    if ($suspended -and $suspendWhy -ne 'NONE') {
        $sev = if ($suspendWhy -eq 'SUSPEND_FROM_PARTNER') { 'Error' } else { 'Warning' }
        Emit-AGResult -AGName $agName -DatabaseName $dbName -ReplicaServer $replica `
            -ReplicaRole $role -SyncState $syncState -ConnState $connState `
            -SuspendReason $suspendWhy -IsDataMovementSuspended $suspended `
            -IsFailoverReady $failoverReady -Status 'SuspendedMovement' `
            -Severity $sev -CheckResult 'SuspendedMovement' `
            -Message "Data movement suspended on replica '$replica' DB '$dbName'. Reason: $suspendWhy."
        continue
    }

    # --- Check 3: Synchronization state ---
    $expectedSync = switch ($role) {
        'PRIMARY'   { @('SYNCHRONIZED', 'SYNCHRONIZING', 'N/A') }
        'SECONDARY' { @('SYNCHRONIZED', 'SYNCHRONIZING') }
        default     { @() }
    }
    if ($syncState -notin $expectedSync -and $syncState -ne 'N/A') {
        Emit-AGResult -AGName $agName -DatabaseName $dbName -ReplicaServer $replica `
            -ReplicaRole $role -SyncState $syncState -ConnState $connState `
            -SuspendReason $suspendWhy -IsDataMovementSuspended $suspended `
            -IsFailoverReady $failoverReady -Status $syncState `
            -Severity 'Error' -CheckResult 'NotSynchronizing' `
            -Message "DB '$dbName' on replica '$replica' in AG '$agName' is NOT SYNCHRONIZING. State: $syncState."
        continue
    }

    # --- Healthy ---
    Emit-AGResult -AGName $agName -DatabaseName $dbName -ReplicaServer $replica `
        -ReplicaRole $role -SyncState $syncState -ConnState $connState `
        -SuspendReason $suspendWhy -IsDataMovementSuspended $suspended `
        -IsFailoverReady $failoverReady -Status $syncState `
        -Severity 'OK' -CheckResult 'Healthy' `
        -Message "DB '$dbName' on replica '$replica' in AG '$agName' is healthy. State: $syncState."
}

# --- Check 4: Automatic failover readiness per AG ---
foreach ($agName in $agFailoverReady.Keys) {
    if (-not $agFailoverReady[$agName]) {
        $line = ("ScriptName=$SCRIPT_NAME,InstanceName=$AgentInstanceName,AGName=$agName," +
                 "DatabaseName=(AG Level),Status=NoAutomaticFailoverReady,Severity=Error," +
                 "CheckResult=NoAutomaticFailoverReady," +
                 "Message=AG '$agName' has no secondary replica ready for automatic failover.")
        Write-LogEntry -Line $line
        Write-EventEntry -Message $line -EntryType 'Error' -EventId 3002
    }
}
