// =============================================================================
// modules/dcr.bicep
// Data Collection Rule – SQL Server Monitoring
//
// Collects:
//   • Windows Performance Counters (SQL Server, Process)
//   • Windows Event Logs (Application: MSSQLSERVER, System: SCM)
//   • Custom Logs (SQLMonitoring_CL) from PowerShell scripts
// =============================================================================

param location string
param workspaceResourceId string
param dataCollectionEndpointId string = ''
param tags object = {}

// ---------------------------------------------------------------------------
// Data Collection Rule
// ---------------------------------------------------------------------------

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'DCR-SQLServer-Monitoring'
  location: location
  tags: tags
  properties: {
    description: 'Collects SQL Server performance counters, Windows event logs, and custom script output. Migrated from SCOM Microsoft SQL Server Management Pack.'
    dataCollectionEndpointId: !empty(dataCollectionEndpointId) ? dataCollectionEndpointId : null

    // -----------------------------------------------------------------------
    // Data Sources
    // -----------------------------------------------------------------------
    dataSources: {

      // ---- Performance Counters -------------------------------------------
      performanceCounters: [
        {
          name: 'SQLServerCore'
          streams: [ 'Microsoft-Perf' ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            // SQL Statistics (maps to SCOM rules: SQL Compilations, Batch Requests)
            '\\SQLServer:SQL Statistics\\SQL Compilations/sec'
            '\\SQLServer:SQL Statistics\\SQL Re-Compilations/sec'
            '\\SQLServer:SQL Statistics\\Batch Requests/sec'
            '\\SQLServer:SQL Statistics\\Failed Auto-Params/sec'

            // Buffer Manager (maps to SCOM monitor: Buffer Cache Hit Ratio)
            '\\SQLServer:Buffer Manager\\Buffer cache hit ratio'
            '\\SQLServer:Buffer Manager\\Page reads/sec'
            '\\SQLServer:Buffer Manager\\Page writes/sec'
            '\\SQLServer:Buffer Manager\\Lazy writes/sec'
            '\\SQLServer:Buffer Manager\\Checkpoint pages/sec'
            '\\SQLServer:Buffer Manager\\Page life expectancy'

            // General Statistics (maps to SCOM: Blocking Sessions, User Connections)
            '\\SQLServer:General Statistics\\User Connections'
            '\\SQLServer:General Statistics\\Processes Blocked'
            '\\SQLServer:General Statistics\\Logins/sec'
            '\\SQLServer:General Statistics\\Logouts/sec'
            '\\SQLServer:General Statistics\\Temp Tables Created/sec'

            // Memory Manager (maps to SCOM: Memory-related monitors)
            '\\SQLServer:Memory Manager\\Total Server Memory (KB)'
            '\\SQLServer:Memory Manager\\Target Server Memory (KB)'
            '\\SQLServer:Memory Manager\\Memory Grants Pending'
            '\\SQLServer:Memory Manager\\Memory Grants Outstanding'

            // Databases (maps to SCOM: DB transactions, log flush, log bytes)
            '\\SQLServer:Databases(*)\\Transactions/sec'
            '\\SQLServer:Databases(*)\\Log Flush Wait Time'
            '\\SQLServer:Databases(*)\\Log Bytes Flushed/sec'
            '\\SQLServer:Databases(*)\\Log Flushes/sec'
            '\\SQLServer:Databases(*)\\Active Transactions'
            '\\SQLServer:Databases(*)\\Data File(s) Size (KB)'
            '\\SQLServer:Databases(*)\\Log File(s) Size (KB)'
            '\\SQLServer:Databases(*)\\Log File(s) Used Size (KB)'
            '\\SQLServer:Databases(*)\\Percent Log Used'

            // Locks (maps to SCOM: Average Wait Time, Blocking Sessions)
            '\\SQLServer:Locks(_Total)\\Number of Deadlocks/sec'
            '\\SQLServer:Locks(_Total)\\Lock Requests/sec'
            '\\SQLServer:Locks(_Total)\\Lock Waits/sec'
            '\\SQLServer:Locks(_Total)\\Average Wait Time (ms)'
            '\\SQLServer:Locks(_Total)\\Lock Wait Time (ms)'

            // Access Methods
            '\\SQLServer:Access Methods\\Full Scans/sec'
            '\\SQLServer:Access Methods\\Index Searches/sec'
            '\\SQLServer:Access Methods\\Table Lock Escalations/sec'

            // CPU (maps to SCOM monitor: CPU Utilization %)
            '\\Process(sqlservr)\\% Processor Time'
            '\\Process(sqlservr)\\Working Set'
            '\\Process(sqlservr)\\Thread Count'

            // Availability Replica (maps to SCOM: Sends to Replica/sec)
            '\\SQLServer:Availability Replica(*)\\Bytes Sent to Replica/sec'
            '\\SQLServer:Availability Replica(*)\\Bytes Sent to Transport/sec'
            '\\SQLServer:Availability Replica(*)\\Sends to Replica/sec'
            '\\SQLServer:Availability Replica(*)\\Sends to Transport/sec'
            '\\SQLServer:Availability Replica(*)\\Flow Control/sec'
            '\\SQLServer:Availability Replica(*)\\Resent Messages/sec'

            // Database Replica (maps to SCOM: Redo Blocked/sec, Transaction Delay)
            '\\SQLServer:Database Replica(*)\\Redo Blocked/sec'
            '\\SQLServer:Database Replica(*)\\Transaction Delay'
            '\\SQLServer:Database Replica(*)\\Redo Bytes Remaining'
            '\\SQLServer:Database Replica(*)\\Recovery Queue'
            '\\SQLServer:Database Replica(*)\\File Bytes Received/sec'
            '\\SQLServer:Database Replica(*)\\Log Bytes Received/sec'

            // Resource Pool (maps to SCOM: Resource Pool memory counters)
            '\\SQLServer:Resource Pool Stats(*)\\Max Memory (KB)'
            '\\SQLServer:Resource Pool Stats(*)\\Used Memory (KB)'

            // Disk I/O (maps to SCOM: DB Disk Read/Write Latency – disabled in SCOM)
            '\\PhysicalDisk(*)\\Avg. Disk sec/Read'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
            '\\PhysicalDisk(*)\\Disk Transfers/sec'
          ]
        }
      ]

      // ---- Windows Event Logs ---------------------------------------------
      windowsEventLogs: [
        {
          // Application log – MSSQLSERVER errors/warnings
          // XPath restricts to MSSQLSERVER provider, Level 1 (Critical) and 2 (Error)
          // Maps to SCOM event rules: DBCC errors, login failures, tempdb, service broker, table errors, etc.
          name: 'SQLAppErrors'
          streams: [ 'Microsoft-Event' ]
          xPathQueries: [
            'Application!*[System[Provider[@Name="MSSQLSERVER"] and (Level=1 or Level=2)]]'
            'Application!*[System[Provider[@Name="MSSQLSERVER"] and (Level=3)]]'                        // Warning
            'Application!*[System[Provider[@Name="SQLSERVERAGENT"] and (Level=1 or Level=2)]]'          // Agent errors
            'Application!*[System[Provider[@Name="SQLISService100"] and (Level=1 or Level=2)]]'         // SSIS errors
            'Application!*[System[Provider[@Name="SQLISService110"] and (Level=1 or Level=2)]]'
            'Application!*[System[Provider[@Name="SQLISService120"] and (Level=1 or Level=2)]]'
            'Application!*[System[Provider[@Name="SQLISService130"] and (Level=1 or Level=2)]]'
            'Application!*[System[Provider[@Name="SQLISService140"] and (Level=1 or Level=2)]]'
            'Application!*[System[Provider[@Name="SQLISService150"] and (Level=1 or Level=2)]]'
          ]
        }
        {
          // System log – Service Control Manager for SQL Server service state changes
          // Maps to SCOM monitor: SQL Server Windows Service, SQL Agent Service, SSIS Service
          name: 'SQLServiceState'
          streams: [ 'Microsoft-Event' ]
          xPathQueries: [
            'System!*[System[Provider[@Name="Service Control Manager"] and EventID=7036]]'
            'System!*[System[Provider[@Name="Service Control Manager"] and EventID=7034]]'  // Unexpected service termination
            'System!*[System[Provider[@Name="Service Control Manager"] and EventID=7031]]'  // Service terminated unexpectedly
          ]
        }
      ]

      // ---- Custom Logs (script output → SQLMonitoring_CL) -----------------
      logFiles: [
        {
          name: 'SQLMonitoringScripts'
          streams: [ 'Custom-SQLMonitoring_CL' ]
          filePatterns: [
            'C:\\SQLMonitoring\\Logs\\*.log'
          ]
          format: 'text'
          settings: {
            text: {
              recordStartTimestampFormat: 'YYYY-MM-DD HH:MM:SS'
            }
          }
        }
      ]
    }

    // -----------------------------------------------------------------------
    // Destinations
    // -----------------------------------------------------------------------
    destinations: {
      logAnalytics: [
        {
          name: 'SQLMonitorWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }

    // -----------------------------------------------------------------------
    // Data Flows
    // -----------------------------------------------------------------------
    dataFlows: [
      {
        streams: [ 'Microsoft-Perf' ]
        destinations: [ 'SQLMonitorWorkspace' ]
        transformKql: 'source'
        outputStream: 'Microsoft-Perf'
      }
      {
        streams: [ 'Microsoft-Event' ]
        destinations: [ 'SQLMonitorWorkspace' ]
        transformKql: 'source'
        outputStream: 'Microsoft-Event'
      }
      {
        // KQL transformation: parse key=value pairs written by PowerShell scripts
        // Input format: "ScriptName=Test-SQLAgentJobStatus,JobName=DailyBackup,Status=Failed,Message=Job failed,Severity=Error"
        streams: [ 'Custom-SQLMonitoring_CL' ]
        destinations: [ 'SQLMonitorWorkspace' ]
        transformKql: '''
          source
          | extend RawData = trim(" ", RawData)
          | extend ScriptName  = extract(@"ScriptName=([^,\r\n]+)",  1, RawData)
          | extend JobName     = extract(@"JobName=([^,\r\n]+)",     1, RawData)
          | extend Status      = extract(@"Status=([^,\r\n]+)",      1, RawData)
          | extend Message     = extract(@"Message=([^,\r\n]+)",     1, RawData)
          | extend Severity    = extract(@"Severity=([^,\r\n]+)",    1, RawData)
          | extend InstanceName= extract(@"InstanceName=([^,\r\n]+)",1, RawData)
          | extend DatabaseName= extract(@"DatabaseName=([^,\r\n]+)",1, RawData)
          | extend MetricValue = extract(@"MetricValue=([^,\r\n]+)", 1, RawData)
          | extend CheckResult = extract(@"CheckResult=([^,\r\n]+)", 1, RawData)
          | project
              TimeGenerated,
              Computer,
              ScriptName,
              InstanceName,
              DatabaseName,
              JobName,
              Status,
              Severity,
              Message,
              MetricValue,
              CheckResult,
              RawData
        '''
        outputStream: 'Custom-SQLMonitoring_CL'
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output dcrId string = dcr.id
output dcrImmutableId string = dcr.properties.immutableId
