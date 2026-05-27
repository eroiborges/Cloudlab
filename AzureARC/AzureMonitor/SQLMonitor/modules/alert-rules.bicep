// =============================================================================
// modules/alert-rules.bicep
// Azure Monitor Alert Rules – SQL Server Monitoring
//
// SCOM Severity → Azure Monitor Severity mapping:
//   SCOM Error    → Sev 1  (High)
//   SCOM Warning  → Sev 2  (Medium)
//   SCOM Info     → Sev 3  (Low)
//   SCOM High Pri → Sev 0  (Critical)
// =============================================================================

param location string
param workspaceResourceId string
param actionGroupResourceId string
param tags object = {}


// ---------------------------------------------------------------------------
// 1. SQL Server Windows Service Down
//    SCOM Monitor: "SQL Server Windows Service" – Error, AutoResolve
//    Azure: Scheduled Query Rule on SQLMonitoring_CL (script-based, state-based)
//    Note: Event ID 7036 (SCM transition) was replaced because it only fires at
//    the moment of state change. A pre-existing stopped service produces no event
//    within the alert window. The script writes current state every 5 minutes.
// ---------------------------------------------------------------------------
resource alertSQLServiceDown 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-service-down'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Windows Service has stopped. Migrated from SCOM monitor: SQL Server Windows Service.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLServiceHealth"
            | extend ServiceCategory = extract(@"ServiceCategory=([^,\r\n]+)", 1, RawData)
            | where ServiceCategory == "SQLEngine"
            | where Status == "Stopped" or Status == "NotFound"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, Status, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 2. SQL Server Agent Service Down
//    SCOM Monitor: "SQL Server Agent Service" – Error, AutoResolve
//    Note: Changed from Event 7036 to SQLMonitoring_CL for same reason as #1.
// ---------------------------------------------------------------------------
resource alertSQLAgentDown 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sqlagent-service-down'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Agent Service has stopped. Migrated from SCOM monitor: SQL Server Agent Service.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLServiceHealth"
            | extend ServiceCategory = extract(@"ServiceCategory=([^,\r\n]+)", 1, RawData)
            | where ServiceCategory == "SQLAgent"
            | where Status == "Stopped" or Status == "NotFound"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, Status, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 3. SQL Server CPU Utilization – Dynamic Threshold (Metric-style via Log)
//    SCOM Monitor: "CPU Utilization (%)" – Error
//    Azure: Scheduled Query Rule with dynamic threshold baseline
// ---------------------------------------------------------------------------
resource alertCPUHigh 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-cpu-high'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server process CPU utilization exceeds 90%. Migrated from SCOM monitor: CPU Utilization (%).'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "Process" and CounterName == "% Processor Time"
            | where InstanceName =~ "sqlservr"
            | summarize AvgCPU = avg(CounterValue), _ResourceId = any(_ResourceId) by Computer, bin(TimeGenerated, 5m)
            | where AvgCPU > 90
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 3
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Buffer Cache Hit Ratio Low
//    SCOM Monitor: "Buffer Cache Hit Ratio" – Error (disabled, enable via override)
//    Azure: Scheduled Query Rule – Severity 1
// ---------------------------------------------------------------------------
resource alertBufferCacheLow 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-buffer-cache-low'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Buffer Cache Hit Ratio dropped below 90%. Migrated from SCOM monitor: Buffer Cache Hit Ratio.'
    severity: 1
    enabled: false   // Disabled by default, matching SCOM default
    evaluationFrequency: 'PT10M'
    windowSize: 'PT30M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "SQLServer:Buffer Manager" and CounterName == "Buffer cache hit ratio"
            | summarize AvgRatio = avg(CounterValue), _ResourceId = any(_ResourceId) by Computer, bin(TimeGenerated, 10m)
            | where AvgRatio < 90
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 3
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 5. Database in Unhealthy State
//    SCOM Monitor: "Database Status" – MatchMonitorHealth
// ---------------------------------------------------------------------------
resource alertDBStatus 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-database-unhealthy'
  location: location
  tags: tags
  properties: {
    description: 'A SQL Server database is in an offline, suspect, or recovering state. Migrated from SCOM monitor: Database Status.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLDatabaseHealth"
            | where Status in ("OFFLINE", "SUSPECT", "RECOVERING", "RECOVERY_PENDING", "RESTORING", "EMERGENCY")
            | project TimeGenerated, Computer, _ResourceId, InstanceName, DatabaseName, Status, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'DatabaseName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 6. Database Backup Overdue
//    SCOM Monitor: "Database Backup Status" – Error (disabled by default)
// ---------------------------------------------------------------------------
resource alertBackupOverdue 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-backup-overdue'
  location: location
  tags: tags
  properties: {
    description: 'A SQL Server database has not been backed up within the expected window. Migrated from SCOM monitor: Database Backup Status.'
    severity: 1
    enabled: false   // Disabled by default, matching SCOM default
    evaluationFrequency: 'PT1H'
    windowSize: 'PT2H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLDatabaseHealth"
            | where CheckResult == "BackupOverdue"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, DatabaseName, Message, MetricValue
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'DatabaseName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 7. Database Log Backup Overdue
//    SCOM Monitor: "Database Log Backup Status" – Error (disabled by default)
// ---------------------------------------------------------------------------
resource alertLogBackupOverdue 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-log-backup-overdue'
  location: location
  tags: tags
  properties: {
    description: 'A SQL Server database transaction log has not been backed up within the expected window. Migrated from SCOM monitor: Database Log Backup Status.'
    severity: 1
    enabled: false
    evaluationFrequency: 'PT1H'
    windowSize: 'PT2H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLDatabaseHealth"
            | where CheckResult == "LogBackupOverdue"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, DatabaseName, Message, MetricValue
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'DatabaseName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 8. SQL Agent Job Failure
//    SCOM Monitor: "Last Run Status" – Warning
// ---------------------------------------------------------------------------
resource alertAgentJobFailed 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-agentjob-failed'
  location: location
  tags: tags
  properties: {
    description: 'A SQL Server Agent job has failed. Migrated from SCOM monitor: Last Run Status.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLAgentJobStatus"
            | where Status == "Failed"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, JobName, Message, MetricValue
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'JobName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 9. Blocking Sessions Detected
//    SCOM Monitor: "Blocking Sessions" – Error/High (disabled by default)
// ---------------------------------------------------------------------------
resource alertBlockingSessions 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-blocking-sessions'
  location: location
  tags: tags
  properties: {
    description: 'Blocking sessions detected on SQL Server. Migrated from SCOM monitor: Blocking Sessions (disabled by default).'
    severity: 1
    enabled: false
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "SQLServer:General Statistics" and CounterName == "Processes Blocked"
            | summarize MaxBlocked = max(CounterValue), _ResourceId = any(_ResourceId) by Computer, bin(TimeGenerated, 5m)
            | where MaxBlocked > 5
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 10. Availability Group Data Synchronization Issue
//     SCOM Monitor: "Availability Database Data Synchronization" – MatchMonitorHealth
//     SCOM Monitor: "Availability Replicas Data Synchronization (Windows rollup)"
// ---------------------------------------------------------------------------
resource alertAGSyncIssue 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-ag-sync-issue'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Availability Group replica data synchronization issue detected. Migrated from SCOM monitor: Availability Database Data Synchronization.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLAvailabilityGroup"
            | where CheckResult in ("NotSynchronizing", "Disconnected", "SuspendedMovement")
            | project TimeGenerated, Computer, _ResourceId, InstanceName, DatabaseName, Status, Message, CheckResult
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'DatabaseName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 11. Availability Replica Role Changed
//     SCOM Rule: "MSSQL on Windows: Availability Replica Role Changed" – Alert Sev 1
// ---------------------------------------------------------------------------
resource alertAGRoleChange 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-ag-role-changed'
  location: location
  tags: tags
  properties: {
    description: 'An Availability Replica has changed its role (failover may have occurred). Migrated from SCOM rule: Availability Replica Role Changed.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source == "MSSQLSERVER"
            | where EventID in (1480, 19406)
            | project TimeGenerated, Computer, _ResourceId, EventID, RenderedDescription
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 12. Log Shipping Destination Delay
//     SCOM Monitor: "Destination Log Shipping" – Error
// ---------------------------------------------------------------------------
resource alertLogShippingDelay 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-logshipping-delay'
  location: location
  tags: tags
  properties: {
    description: 'Log shipping destination has not received a log restore within threshold. Migrated from SCOM monitor: Destination Log Shipping.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLDatabaseHealth"
            | where CheckResult == "LogShippingDelay"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, DatabaseName, Message, MetricValue
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'DatabaseName'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 13. Database Consistency Errors (DBCC)
//     SCOM Rule: "MSSQL on Windows: Database consistency errors found" – Error Sev 2
// ---------------------------------------------------------------------------
resource alertDBCCErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-dbcc-errors'
  location: location
  tags: tags
  properties: {
    description: 'DBCC check found database consistency errors. Migrated from SCOM rule: Database consistency errors found.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source == "MSSQLSERVER"
            | where EventID in (2570, 2601, 2627, 8928, 8929, 8930, 8964, 8965, 8966)
            | project TimeGenerated, Computer, _ResourceId, EventID, RenderedDescription
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 14. SQL Server Fatal Errors (Severity 17-25)
//     SCOM Rule: Various table errors, B-tree errors, page errors – Error Sev 2
// ---------------------------------------------------------------------------
resource alertSQLFatalErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-fatal-errors'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server fatal errors (severity 17+) detected in event log. Covers SCOM rules: table errors, B-tree errors, invalid page references.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source == "MSSQLSERVER"
            | where EventID in (
                823, 824, 825,      // I/O errors
                832, 833,           // Buffer errors
                855, 856,           // Memory errors
                3414, 3421,         // Recovery errors
                17204, 17207,       // File open errors
                9001, 9002,         // Log unavailable / full
                605,                // Allocation page fetch error
                2534, 2533          // Page allocation errors
            )
            | project TimeGenerated, Computer, _ResourceId, EventID, RenderedDescription
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 15. Login Failures
//     SCOM Rules: Login failed – Error during validation, Password too short
// ---------------------------------------------------------------------------
resource alertLoginFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-login-failures'
  location: location
  tags: tags
  properties: {
    description: 'Elevated SQL Server login failure rate detected. Migrated from SCOM rules: Login failed (Error during validation / Password too short).'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source == "MSSQLSERVER"
            | where EventID in (18456, 18464, 18468, 18486, 18487, 18488)
            | summarize LoginFailureCount = count(), _ResourceId = any(_ResourceId) by Computer, bin(TimeGenerated, 5m)
            | where LoginFailureCount > 10
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 16. SQL Server Agent Cannot Connect
//     SCOM Rule: "SQL Server Agent is unable to connect to SQL Server" – Warning Sev 1
// ---------------------------------------------------------------------------
resource alertAgentConnectFail 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sqlagent-connect-fail'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Agent cannot connect to SQL Server instance. Migrated from SCOM rule: SQL Server Agent is unable to connect to SQL Server.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source == "SQLSERVERAGENT"
            | where EventID in (103, 208, 312, 315, 317)
            | project TimeGenerated, Computer, _ResourceId, EventID, RenderedDescription
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 17. SSIS Service Health
//     SCOM Monitor: "Integration Service Health Status" – Error
//     Note: Changed from Event 7036 to SQLMonitoring_CL for same reason as #1.
// ---------------------------------------------------------------------------
resource alertSSISDown 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ssis-service-down'
  location: location
  tags: tags
  properties: {
    description: 'SQL Server Integration Services (SSIS) service has stopped. Migrated from SCOM monitor: Integration Service Health Status.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLServiceHealth"
            | extend ServiceCategory = extract(@"ServiceCategory=([^,\r\n]+)", 1, RawData)
            | where ServiceCategory == "SSIS"
            | where Status == "Stopped" or Status == "NotFound"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, Status, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 18. SSIS Package Execution Failed
//     SCOM Rule: "Integration Service Package Failed" – Error Sev 2
// ---------------------------------------------------------------------------
resource alertSSISPackageFailed 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ssis-package-failed'
  location: location
  tags: tags
  properties: {
    description: 'An SSIS package failed during execution. Migrated from SCOM rule: Integration Service Package Failed.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source startswith "SQLISService"
            | where EventID == 12288
            | project TimeGenerated, Computer, _ResourceId, EventID, RenderedDescription
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 19. Disk Write Latency High
//     SCOM Monitor: "DB Engine Disk Write Latency" – MatchMonitorHealth/High (disabled)
// ---------------------------------------------------------------------------
resource alertDiskWriteLatency 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-disk-write-latency'
  location: location
  tags: tags
  properties: {
    description: 'Disk write latency for SQL Server data volume exceeds 20ms. Migrated from SCOM monitor: DB Engine Disk Write Latency (disabled by default).'
    severity: 2
    enabled: false
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "PhysicalDisk" and CounterName == "Avg. Disk sec/Write"
            | where CounterValue > 0.020  // 20ms threshold
            | summarize AvgLatencyMs = avg(CounterValue * 1000), _ResourceId = any(_ResourceId) by Computer, InstanceName, bin(TimeGenerated, 5m)
            | where AvgLatencyMs > 20
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}

// ---------------------------------------------------------------------------
// 20. Availability Group Automatic Failover Not Ready
//     SCOM Monitor: "Availability Group Automatic Failover (rollup)" – Error
// ---------------------------------------------------------------------------
resource alertAGFailoverNotReady 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-ag-failover-not-ready'
  location: location
  tags: tags
  properties: {
    description: 'No secondary replica is ready for automatic failover in the Availability Group. Migrated from SCOM monitor: Availability Group Automatic Failover.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT10M'
    windowSize: 'PT30M'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            SQLMonitoring_CL
            | where ScriptName == "Test-SQLAvailabilityGroup"
            | where CheckResult == "NoAutomaticFailoverReady"
            | project TimeGenerated, Computer, _ResourceId, InstanceName, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          resourceIdColumn: '_ResourceId'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: ['*']
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [ actionGroupResourceId ]
    }
  }
}
