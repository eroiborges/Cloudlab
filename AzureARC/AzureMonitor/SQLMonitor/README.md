# SQL Server Monitoring – Azure Monitor Migration
## Migrated from: SCOM Microsoft SQL Server Management Pack (Windows)

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Deployment Instructions](#deployment-instructions)
5. [Agent Configuration Steps](#agent-configuration-steps)
6. [Scheduled Task Setup](#scheduled-task-setup)
7. [SQL Server Permissions & Service Account](#sql-server-permissions--service-account)
8. [Workbook Notes](#workbook-notes)
9. [SCOM → Azure Monitor Mapping](#scom--azure-monitor-mapping)
10. [Gap Analysis](#gap-analysis)

---

## Overview

This solution migrates **SQL Server on Windows** monitoring from System Center Operations Manager 2019 to **Azure Monitor**. It replicates all enabled SCOM monitors and alert rules exported from the following Management Packs:

| Management Pack | Key Coverage |
|---|---|
| Microsoft SQL Server on Windows (Monitoring) | DB Engine, Agent, AG, Databases |
| Microsoft SQL Server Core Library | AG rollup monitors |
| Microsoft SQL Server Integration Services on Windows | SSIS service & packages |
| BB – SQL Servers / BB – SQL Jobs | Custom environment monitors |

### What the template creates

This is a **self-contained deployment** — no pre-existing Log Analytics Workspace or Action Group is required.

| Resource | Type | Notes |
|---|---|---|
| Log Analytics Workspace | `Microsoft.OperationalInsights/workspaces` | Created with PerGB2018 SKU, configurable retention |
| `SQLMonitoring_CL` table | `Microsoft.OperationalInsights/workspaces/tables` | Custom log table; created before DCR and alerts |
| Action Group | `Microsoft.Insights/actionGroups` | Email receiver; `location: global` |
| Data Collection Rule | `Microsoft.Insights/dataCollectionRules` | Perf + Event + custom log ingestion |
| 20 Scheduled Query Rules | `Microsoft.Insights/scheduledQueryRules` | Alert rules mapped from SCOM monitors |
| SQL Server Workbook | `Microsoft.Insights/workbooks` | Dashboard replicating SCOM health views |

### Artifact Reference

| Artifact | Path | Purpose |
|---|---|---|
| `main.bicep` | `./main.bicep` | Orchestrates all resources including LAW and Action Group |
| `modules/dcr.bicep` | `./modules/dcr.bicep` | Data Collection Rule (perf counters + event logs + custom logs) |
| `modules/alert-rules.bicep` | `./modules/alert-rules.bicep` | 20 Azure Monitor Scheduled Query Rules |
| `modules/workbook.bicep` | `./modules/workbook.bicep` | Workbook deployment wrapper |
| `workbook/sql-workbook.json` | `./workbook/sql-workbook.json` | Azure Workbook replicating SCOM health views |
| `scripts/Test-SQLServiceHealth.ps1` | `./scripts/` | Service state monitor (SQL Engine, Agent, SSIS) |
| `scripts/Test-SQLAgentJobStatus.ps1` | `./scripts/` | Agent job last-run status + duration |
| `scripts/Test-SQLAvailabilityGroup.ps1` | `./scripts/` | AG replica sync, suspension, failover readiness |
| `scripts/Test-SQLDatabaseHealth.ps1` | `./scripts/` | DB state, backup age, VLF count, log shipping |
| `scripts/Invoke-SQLMonitorLogRotation.ps1` | `./scripts/` | Log file rotation and purge (runs daily at 02:00 AM) |

---

## Architecture

```
SQL Server Host (Azure Arc-enabled)
  │
  ├─ Azure Monitor Agent (AMA)
  │    ├─ Collects: Performance Counters  → Perf table (Log Analytics)
  │    ├─ Collects: Windows Event Logs    → Event table
  │    └─ Collects: Custom Log Files      → SQLMonitoring_CL table
  │
  └─ Scheduled Tasks (every 5 min)
       ├─ Test-SQLServiceHealth.ps1
       ├─ Test-SQLAgentJobStatus.ps1
       ├─ Test-SQLAvailabilityGroup.ps1
       └─ Test-SQLDatabaseHealth.ps1
            └─ Writes key=value logs → C:\SQLMonitoring\Logs\*.log
                                            ↑ ingested by AMA custom log

Azure Monitor / Log Analytics Workspace
  ├─ Perf table         (SQL Server performance counters)
  ├─ Event table        (MSSQLSERVER, SQLSERVERAGENT, SCM events)
  └─ SQLMonitoring_CL   (parsed script output via DCR KQL transform)
       │
       ├─ 20 Scheduled Query Rules (Alert Rules)
       └─ SQL Server Workbook Dashboard
```

---

## Prerequisites

### Azure-side
- Contributor + Monitoring Contributor RBAC on the target Resource Group
- The Log Analytics Workspace, `SQLMonitoring_CL` table, and Action Group are **all created by this template** — no pre-existing resources required

### SQL Server Hosts
- Windows Server 2016 or later
- **Azure Monitor Agent (AMA)** installed (replaces the legacy MMA/OMS agent)
  - Install via Azure Arc for on-premises servers
  - Minimum version: AMA 1.10+
- PowerShell 5.1 or later
- SQL Server account for scripts with the following permissions:
  - `VIEW SERVER STATE` (for AG and blocking session queries)
  - `SELECT` on `msdb.dbo.sysjobs`, `msdb.dbo.sysjobhistory`
  - `SELECT` on `msdb.dbo.log_shipping_monitor_secondary`
  - `SELECT` on `msdb.dbo.backupset`

---

## Deployment Instructions

### Step 1 – Clone / Copy artifacts

Copy this `SQLMonitor/` folder to your deployment workstation.

### Step 2 – Set parameter values

Edit `parameters.json` with your values. All resources are created by the template:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceName": {
      "value": "law-sqlmonitor-prod"
    },
    "workspaceRetentionDays": {
      "value": 30
    },
    "actionGroupName": {
      "value": "ag-sql-monitor"
    },
    "actionGroupShortName": {
      "value": "SQLMonAlert"
    },
    "alertEmailAddress": {
      "value": "ops-team@example.com"
    },
    "sqlServiceName": {
      "value": "MSSQLSERVER"
    },
    "environment": {
      "value": "production"
    },
    "ownerTag": {
      "value": "IT-Operations"
    }
  }
}
```

| Parameter | Description | Default |
|---|---|---|
| `workspaceName` | LAW name — must be globally unique | _(required)_ |
| `workspaceRetentionDays` | Data retention (30 = free tier; >30 billed at ~$0.10/GB/month) | `30` |
| `actionGroupName` | Action Group resource name | `ag-sql-monitor` |
| `actionGroupShortName` | Display short name (max 12 chars) | `SQLMonAlert` |
| `alertEmailAddress` | Email address to receive alert notifications | _(required)_ |
| `sqlServiceName` | Windows service name for the SQL Engine | `MSSQLSERVER` |
| `dataCollectionEndpointId` | Optional: existing DCE resource ID | _(blank)_ |
| `environment` | Tag value | `production` |
| `ownerTag` | Tag value | `IT-Operations` |

> **Named instances:** Set `sqlServiceName` to `MSSQL$INSTANCENAME` (e.g. `MSSQL$SQL2019`).

> **Note on Action Group location:** Action Groups always deploy to `global` in Azure Monitor regardless of the resource group region — this is the correct and expected behavior.

### Step 3 – Deploy via Azure CLI

```bash
# Set variables
monitorrg="<YOUR_RESOURCE_GROUP for deploy Monitor Artifacts>"
arcrg="<YOUR_RESOURCE_GROUP where is the ARC VMs>"
sub="<YOUR_SUBSCRIPTION_ID>"
deployname="SQLMonitorDeploy-$(date +%Y%m%d)"

# Login and set subscription
az login
az account set --subscription "$sub"

# Deploy Monitor artifacts to the monitoring resource group
az deployment group create \
  --resource-group "$monitorrg" \
  --template-file main.bicep \
  --parameters @parameters.json \
  --name "$deployname"
```

### Step 4 – Associate DCR with SQL Server machines

After deployment, associate the DCR with each SQL Server (Arc-enabled) machine:

```bash
# $monitorrg, $arcrg and $deployname defined in Step 3
machines=("<MACHINE_NAME_1>" "<MACHINE_NAME_2>")   # add one entry per Arc-enabled SQL Server

# Get the DCR Resource ID from the Monitor artifacts resource group
DCR_ID=$(az deployment group show \
  --resource-group "$monitorrg" \
  --name "$deployname" \
  --query "properties.outputs.dcrResourceId.value" -o tsv)

# Associate the DCR with each Arc machine (looked up from the Arc resource group)
for machinename in "${machines[@]}"; do
  arcvmid=$(az connectedmachine show --name "$machinename" --resource-group "$arcrg" --query id -o tsv)
  az monitor data-collection rule association create \
    --name "SQL-DCR-Association" \
    --resource "$arcvmid" \
    --rule-id "$DCR_ID"
  echo "Associated DCR with: $machinename"
done
```

> Add each Arc-enabled SQL Server machine name to the `machines` array. The `az connectedmachine show` call resolves the full resource ID automatically — no need to hardcode subscription or resource group paths.

### Step 5 – Custom log table

The `SQLMonitoring_CL` table is **automatically created by this template** with the correct schema before the DCR and alert rules deploy. No manual step required.

---

## Agent Configuration Steps

### 1. Install Azure Monitor Agent

**Azure Arc-enabled servers (on-premises):**
```bash
# $arcrg defined in Step 3; set machine-specific variables
machinename="<YOUR_ARC_MACHINE_NAME>"
location="<YOUR_LOCATION>"   # e.g. southcentralus

az connectedmachine extension create \
  --name AzureMonitorWindowsAgent \
  --resource-group "$arcrg" \
  --machine-name "$machinename" \
  --location "$location" \
  --type AzureMonitorWindowsAgent \
  --publisher Microsoft.Azure.Monitor
```

**Azure VMs:**
```bash
# $arcrg defined in Step 3
vmname="<YOUR_VM_NAME>"

az vm extension set \
  --resource-group "$arcrg" \
  --vm-name "$vmname" \
  --name AzureMonitorWindowsAgent \
  --publisher Microsoft.Azure.Monitor \
  --version 1.10
```

### 2. Verify agent is running

```powershell
Get-Service -Name AzureMonitorAgent
# Expected: Status = Running
```

### 3. Create the script log directory on each SQL Server

---

## Scheduled Task Setup

> **Recommended:** Use a dedicated service account (`svc-sqlmonitor`) instead of `SYSTEM`.
> See [SQL Server Permissions & Service Account](#sql-server-permissions--service-account) for setup instructions.
> Once the account is created, set `$RunAsUser` to `DOMAIN\svc-sqlmonitor` or `HOSTNAME\svc-sqlmonitor`.

### Step 1 – Create the scripts directory

Run on the SQL Server host with local Administrator rights:

```powershell
New-Item -ItemType Directory -Path "C:\SQLMonitoring\Scripts" -Force
New-Item -ItemType Directory -Path "C:\SQLMonitoring\Logs"    -Force
Write-Host "Directories created."
```

### Step 2 – Copy the monitoring scripts

Manually copy the five `.ps1` files from this repository's `scripts\` folder into `C:\SQLMonitoring\Scripts\` on the SQL Server host:

```
scripts\
  Test-SQLServiceHealth.ps1
  Test-SQLAgentJobStatus.ps1
  Test-SQLAvailabilityGroup.ps1
  Test-SQLDatabaseHealth.ps1
  Invoke-SQLMonitorLogRotation.ps1
```

Use whichever transfer method fits your environment (file share, USB, SCCM software distribution, SCP, etc.). When done, verify the files are in place:

```powershell
Get-ChildItem "C:\SQLMonitoring\Scripts\*.ps1" | Select-Object Name
# Expected: five files listed above
```

> Do not proceed to Step 3 until all five files are confirmed present.

### Step 3 – Register the Scheduled Tasks

Run the following block on the SQL Server host. Adjust `$InstanceName`, `$AgentInstanceName`, and `$RunAsUser` for your environment:

```powershell
# -----------------------------------------------------------------------
# Parameters – edit these before running
# -----------------------------------------------------------------------
$ScriptDir         = "C:\SQLMonitoring\Scripts"
$InstanceName      = "localhost"        # or "localhost\SQL2019" for named instance
$AgentInstanceName = "MSSQLSERVER"     # Windows service label
$RunAsUser         = "SYSTEM"          # replace with DOMAIN\svc-sqlmonitor (recommended)
# -----------------------------------------------------------------------

$tasks = @(
    @{
        TaskName   = "SQLMonitor-ServiceHealth"
        Script     = "$ScriptDir\Test-SQLServiceHealth.ps1"
        Arguments  = "-InstanceName `"$AgentInstanceName`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-AgentJobStatus"
        Script     = "$ScriptDir\Test-SQLAgentJobStatus.ps1"
        Arguments  = "-InstanceName `"$InstanceName`" -AgentInstanceName `"$AgentInstanceName`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-AvailabilityGroup"
        Script     = "$ScriptDir\Test-SQLAvailabilityGroup.ps1"
        Arguments  = "-InstanceName `"$InstanceName`" -AgentInstanceName `"$AgentInstanceName`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-DatabaseHealth"
        Script     = "$ScriptDir\Test-SQLDatabaseHealth.ps1"
        Arguments  = "-InstanceName `"$InstanceName`" -AgentInstanceName `"$AgentInstanceName`""
        RepeatMins = 10
    }
)

foreach ($task in $tasks) {
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$($task.Script)`" $($task.Arguments)"
    $trigger   = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes $task.RepeatMins) -Once -At (Get-Date)
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $task.TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal -Force
    Write-Host "Registered: $($task.TaskName)"
}
```

Then register the **log rotation** task (runs once daily at 02:00 AM):

```powershell
# Log rotation – runs daily at 02:00 AM
# Rotates files > 50 MB, purges archives older than 7 days
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-SQLMonitorLogRotation.ps1`""
$trigger   = New-ScheduledTaskTrigger -Daily -At "02:00"
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SQLMonitor-LogRotation" -Action $action `
    -Trigger $trigger -Settings $settings -Principal $principal -Force
Write-Host "Registered: SQLMonitor-LogRotation"
```

> **How rotation works with AMA:**
> AMA tracks the last read position (byte offset) per file in `C:\ProgramData\Microsoft\AzureMonitorAgent\`.
> When a file is rotated (renamed), AMA treats the new empty file as a fresh source — **no duplicate ingestion**.
> The renamed archive is ignored by AMA since its file pattern no longer matches `*.log` being actively tracked.

### Step 4 – Verify log files

After the first execution cycle (within 10 minutes of task registration), all four log files should be present in `C:\SQLMonitoring\Logs\`:

| Log file | Written by |
|---|---|
| `ServiceHealth.log` | `Test-SQLServiceHealth.ps1` |
| `AgentJobStatus.log` | `Test-SQLAgentJobStatus.ps1` |
| `AGStatus.log` | `Test-SQLAvailabilityGroup.ps1` |
| `DatabaseHealth.log` | `Test-SQLDatabaseHealth.ps1` |

```powershell
Get-ChildItem "C:\SQLMonitoring\Logs\*.log" | Select-Object Name, LastWriteTime, Length
# Expected: 4 files, all with a recent LastWriteTime
```

If fewer than 4 files appear, the missing script failed. Check the Windows Application Event Log filtered on source `ADMonitoringScript` for the error detail:

```powershell
Get-EventLog -LogName Application -Source ADMonitoringScript -Newest 20 |
    Select-Object TimeGenerated, EntryType, Message |
    Format-List
```

---

## SQL Server Permissions & Service Account

The four monitoring scripts connect to SQL Server using **Windows Authentication**. Running them as `SYSTEM` works but grants broader OS access than needed. The recommended approach is a **dedicated low-privilege service account** with only the SQL Server permissions the scripts actually require.

---

### What each script needs

| Script | SQL objects accessed | Minimum SQL permission |
|---|---|---|
| `Test-SQLServiceHealth.ps1` | None — queries Windows services only via `Get-Service` | _(no SQL login needed)_ |
| `Test-SQLAgentJobStatus.ps1` | `msdb.dbo.sysjobs`, `msdb.dbo.sysjobhistory`, `msdb.dbo.agent_datetime` | `SQLAgentReaderRole` in msdb |
| `Test-SQLAvailabilityGroup.ps1` | `sys.availability_groups`, `sys.availability_replicas`, `sys.dm_hadr_availability_replica_states`, `sys.dm_hadr_database_replica_states` | `VIEW SERVER STATE` |
| `Test-SQLDatabaseHealth.ps1` | `sys.databases`, `msdb.dbo.backupset`, `DBCC LOGINFO` (via `sp_MSforeachdb`), `msdb.dbo.log_shipping_monitor_secondary` | `VIEW SERVER STATE` + msdb grants |

---

### Step 1 — Create the Windows service account

**Option A: Domain account** (recommended for domain-joined servers)
```powershell
# Run on a domain controller or with AD module
New-ADUser `
  -Name           "svc-sqlmonitor" `
  -SamAccountName "svc-sqlmonitor" `
  -UserPrincipalName "svc-sqlmonitor@DOMAIN.LOCAL" `
  -AccountPassword (Read-Host -AsSecureString "Password") `
  -PasswordNeverExpires $true `
  -CannotChangePassword $true `
  -Enabled $true
```

**Option B: Local account** (for standalone/workgroup servers — run on each SQL Server host)
```powershell
$pwd = Read-Host -AsSecureString "Service account password"
New-LocalUser -Name "svc-sqlmonitor" `
              -Password $pwd `
              -PasswordNeverExpires $true `
              -UserMayNotChangePassword $true `
              -Description "SQL Monitor scheduled task account"
```

---

### Step 2 — Grant Windows local rights on each SQL Server host

```powershell
# Grant 'Log on as a batch job' right (required for scheduled tasks)
$account = "DOMAIN\svc-sqlmonitor"   # or "$env:COMPUTERNAME\svc-sqlmonitor" for local

$sidStr  = (New-Object System.Security.Principal.NTAccount($account)).Translate(
              [System.Security.Principal.SecurityIdentifier]).Value

$tmpFile = [System.IO.Path]::GetTempFileName()
secedit /export /cfg $tmpFile /quiet
$cfg = Get-Content $tmpFile
$cfg = $cfg -replace `
  '(SeBatchLogonRight\s*=\s*)(.*)', `
  "`$1`$2,$sidStr"
Set-Content $tmpFile $cfg
secedit /configure /cfg $tmpFile /db secedit.sdb /quiet
Remove-Item $tmpFile

# Grant write access to the log directory
$logDir = "C:\SQLMonitoring\Logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$acl = Get-Acl $logDir
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $account, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($rule)
Set-Acl $logDir $acl
Write-Host "Local rights granted to $account"
```

---

### Step 3 — Create the SQL Server login and grant permissions

Run the following T-SQL on each SQL Server instance as `sysadmin`:

```sql
-- ===========================================================================
-- Setup: SQL Monitor service account permissions
-- Replace DOMAIN\svc-sqlmonitor with your actual account name.
-- For a local account use: HOSTNAME\svc-sqlmonitor
-- ===========================================================================

USE [master];
GO

-- 1. Create the Windows login
CREATE LOGIN [DOMAIN\svc-sqlmonitor] FROM WINDOWS
    WITH DEFAULT_DATABASE = [master];
GO

-- 2. Grant server-level permission
--    VIEW SERVER STATE covers:
--      - sys.dm_hadr_* DMVs (Availability Groups)
--      - DBCC LOGINFO in all databases (VLF count)
GRANT VIEW SERVER STATE TO [DOMAIN\svc-sqlmonitor];
GO

-- 3. msdb permissions
USE [msdb];
GO

CREATE USER [DOMAIN\svc-sqlmonitor]
    FOR LOGIN [DOMAIN\svc-sqlmonitor];
GO

-- SQLAgentReaderRole covers: sysjobs, sysjobhistory, agent_datetime
ALTER ROLE [SQLAgentReaderRole]
    ADD MEMBER [DOMAIN\svc-sqlmonitor];
GO

-- Backup age query
GRANT SELECT ON dbo.backupset
    TO [DOMAIN\svc-sqlmonitor];
GO

-- Log shipping delay query (only needed if log shipping is in use)
GRANT SELECT ON dbo.log_shipping_monitor_secondary
    TO [DOMAIN\svc-sqlmonitor];
GO
```

---

### Step 4 — Pre-create the Windows Event Log source (one-time, as admin)

The scripts register an Application Event Log source (`ADMonitoringScript`) on first run. Creating a new Event Log source requires local Administrator rights. Pre-create it once so the service account never needs elevation:

```powershell
# Run once per host with local Administrator rights
if (-not [System.Diagnostics.EventLog]::SourceExists('ADMonitoringScript')) {
    [System.Diagnostics.EventLog]::CreateEventSource('ADMonitoringScript', 'Application')
    Write-Host "Event source 'ADMonitoringScript' created."
} else {
    Write-Host "Event source already exists."
}
```

---

### Step 5 — Register the Scheduled Tasks using the service account

In the [Scheduled Task Setup](#scheduled-task-setup) script, set `$RunAsUser` to the service account and provide the password:

```powershell
# Domain account
.\Deploy-SQLMonitoringTasks.ps1 `
    -RunAsUser "DOMAIN\svc-sqlmonitor"

# Local account
.\Deploy-SQLMonitoringTasks.ps1 `
    -RunAsUser "$env:COMPUTERNAME\svc-sqlmonitor"
```

When using a named account (not SYSTEM), `Register-ScheduledTask` will prompt for the password, or you can pass it via `-Password` if scripting unattended:

```powershell
$principal = New-ScheduledTaskPrincipal `
    -UserId   "DOMAIN\svc-sqlmonitor" `
    -LogonType Password `
    -RunLevel Highest
```

---

### Permission summary

| Scope | Object / Right | Purpose |
|---|---|---|
| SQL Server — server level | `VIEW SERVER STATE` | AG DMVs, DBCC LOGINFO |
| SQL Server — msdb | `SQLAgentReaderRole` | sysjobs, sysjobhistory |
| SQL Server — msdb | `SELECT` on `dbo.backupset` | Backup age check |
| SQL Server — msdb | `SELECT` on `dbo.log_shipping_monitor_secondary` | Log shipping delay |
| Windows — local | `Log on as a batch job` | Scheduled task logon |
| Windows — local | `Modify` on `C:\SQLMonitoring\Logs` | Write log files |
| Windows — local | _(no elevation needed after pre-create)_ | Event Log source |

---

## SCOM → Azure Monitor Mapping

### Monitors

| # | SCOM Monitor | Severity | Enabled | Azure Monitor Equivalent | Alert Name |
|---|---|---|---|---|---|
| 1 | SQL Server Windows Service | Error | ✅ | Scheduled Query Rule | `alert-sql-service-down` |
| 2 | SQL Server Agent Service | Error | ✅ | Scheduled Query Rule | `alert-sqlagent-service-down` |
| 3 | CPU Utilization (%) | Error | ✅ | Scheduled Query Rule (>90%) | `alert-sql-cpu-high` |
| 4 | Buffer Cache Hit Ratio | Error | ❌ disabled | Scheduled Query Rule (<90%) | `alert-sql-buffer-cache-low` |
| 5 | Database Status | MatchMonitorHealth | ✅ | Scheduled Query Rule (script) | `alert-sql-database-unhealthy` |
| 6 | Database Backup Status | Error | ❌ disabled | Scheduled Query Rule (script) | `alert-sql-backup-overdue` |
| 7 | Database Log Backup Status | Error | ❌ disabled | Scheduled Query Rule (script) | `alert-sql-log-backup-overdue` |
| 8 | Last Run Status (Agent Job) | Warning | ✅ | Scheduled Query Rule (script) | `alert-sql-agentjob-failed` |
| 9 | Blocking Sessions | Error/High | ❌ disabled | Scheduled Query Rule (Perf) | `alert-sql-blocking-sessions` |
| 10 | Availability Database Data Synchronization | MatchMonitorHealth | ✅ | Scheduled Query Rule (script) | `alert-sql-ag-sync-issue` |
| 11 | Availability Replica Role Changed | Error | ✅ | Scheduled Query Rule (Event) | `alert-sql-ag-role-changed` |
| 12 | Destination Log Shipping | Error | ✅ | Scheduled Query Rule (script) | `alert-sql-logshipping-delay` |
| 13 | Integration Service Health Status | Error | ✅ | Scheduled Query Rule | `alert-ssis-service-down` |
| 14 | DB Engine Disk Write Latency | MatchMonitorHealth/High | ❌ disabled | Scheduled Query Rule (Perf) | `alert-sql-disk-write-latency` |
| 15 | Availability Group Automatic Failover | Error | ✅ | Scheduled Query Rule (script) | `alert-sql-ag-failover-not-ready` |

### Alert Rules (Events)

| # | SCOM Rule | Event IDs | Azure Monitor Alert |
|---|---|---|---|
| 16 | Database consistency errors found | 2570, 8928-8966 | `alert-sql-dbcc-errors` |
| 17 | Table errors / B-tree errors / page errors | 823,824,825,832,833,9001,9002,605 | `alert-sql-fatal-errors` |
| 18 | Login failed (validation, password) | 18456,18464,18468 | `alert-sql-login-failures` |
| 19 | SQL Agent unable to connect to SQL Server | 103,208,312 | `alert-sqlagent-connect-fail` |
| 20 | Integration Service Package Failed | 12288 | `alert-ssis-package-failed` |

### Performance Counter → Log Analytics Mapping

| SCOM Counter Object | Counter Name | LA Table | KQL Field |
|---|---|---|---|
| SQLServer:SQL Statistics | SQL Compilations/sec | Perf | CounterValue where CounterName == "SQL Compilations/sec" |
| SQLServer:Buffer Manager | Buffer cache hit ratio | Perf | CounterValue |
| SQLServer:General Statistics | Processes Blocked | Perf | CounterValue |
| SQLServer:Memory Manager | Total Server Memory (KB) | Perf | CounterValue |
| SQLServer:Databases(*) | Transactions/sec | Perf | CounterValue per InstanceName |
| SQLServer:Locks(_Total) | Number of Deadlocks/sec | Perf | CounterValue |
| SQLServer:Availability Replica(*) | Sends to Replica/sec | Perf | CounterValue |
| SQLServer:Database Replica(*) | Redo Blocked/sec | Perf | CounterValue |
| SQLServer:Database Replica(*) | Transaction Delay | Perf | CounterValue |
| Process(sqlservr) | % Processor Time | Perf | CounterValue |

### Alert Rule Dimension Splits

All 20 alert rules split on the **`Computer`** dimension so each machine fires its own independent alert instance. Six rules carry a second dimension for finer entity identification:

| Alert rule | Dimensions | Alert fires per |
|---|---|---|
| All 20 rules | `Computer` | Machine |
| `alert-sql-database-unhealthy` | `Computer` + `DatabaseName` | Machine + Database |
| `alert-sql-backup-overdue` | `Computer` + `DatabaseName` | Machine + Database |
| `alert-sql-log-backup-overdue` | `Computer` + `DatabaseName` | Machine + Database |
| `alert-sql-agentjob-failed` | `Computer` + `JobName` | Machine + Job |
| `alert-sql-ag-sync-issue` | `Computer` + `DatabaseName` | Machine + Database |
| `alert-sql-logshipping-delay` | `Computer` + `DatabaseName` | Machine + Database |

**Why this matters:** Without dimension splits, a single alert fires for the entire Log Analytics Workspace scope. When split, the alert title shows the specific machine (and database/job where applicable), and acknowledging one instance does not suppress alerts for other machines. This replicates the SCOM behavior where each monitored object has its own health state.

**Bicep pattern:**

```bicep
dimensions: [
  {
    name: 'Computer'
    operator: 'Include'
    values: ['*']
  }
  {
    name: 'DatabaseName'   // or 'JobName' for agentjob-failed
    operator: 'Include'
    values: ['*']
  }
]
```

---

## Workbook Notes

This section documents known behaviors, design decisions, and fixes applied to `workbook/sql-workbook.json`.

---

### Parameter: SQL Server Host (Computer)

The `Computer` parameter is a multi-select dropdown populated by a KQL query against the `Perf` table. It is configured with an **"All Servers"** sentinel option (`allValue: "*"`, default `["*"]`) so that the workbook renders with all servers visible even before a specific host is selected.

**Why:** KQL `| where Computer in ()` (empty list) is a parse error. The sentinel avoids the empty-list condition:

```kql
| where Computer in ({Computer}) or "*" in ({Computer})
```

When "All" is selected, `{Computer}` expands to `'*'` → `"*" in ('*')` is `true` → all rows pass. When specific hosts are selected, the `"*"` sentinel is absent from the list and `Computer in (...)` filters normally.

---

### Parameter: TimeRange

The `TimeRange` parameter is type 4 (time range picker). It expands to a **partial KQL expression** (e.g., `>= datetime(2026-05-11T00:00:00Z) and TimeGenerated <= datetime(...)`). It must always be prefixed with the column name:

```kql
| where TimeGenerated {TimeRange}   ✅
| where {TimeRange}                 ❌  parse error
```

---

### Service Health panel — data source

The **SQL Server Service States** panel queries `SQLMonitoring_CL`, not the `Event` table. `Test-SQLServiceHealth.ps1` writes structured `key=value` lines to `ServiceHealth.log`, which AMA ingests into `SQLMonitoring_CL` via the DCR transform. It does **not** rely on Windows Service Control Manager events (Event IDs 7036/7034/7031).

The `ServiceCategory` and `ServiceName` fields are not projected by the DCR `transformKql` — they are extracted inline from `RawData`:

```kql
SQLMonitoring_CL
| where ScriptName == "Test-SQLServiceHealth"
| extend ServiceCategory = extract(@"ServiceCategory=([^,\r\n]+)", 1, RawData)
| extend ServiceName     = extract(@"ServiceName=([^,\r\n]+)",     1, RawData)
```

---

### AMA column names — no `_s` suffix

With **Azure Monitor Agent (AMA) + DCR KQL transform**, custom log columns are projected with the names defined in `transformKql` — **no `_s` / `_d` / `_b` type suffixes**.

The `_s` suffix convention belongs to the legacy **Microsoft Monitoring Agent (MMA/OMS)**. If you see `ScriptName_s` errors in queries, the workspace was previously used with MMA. The correct column name with AMA is `ScriptName`.

| Agent | Column convention | Example |
|---|---|---|
| MMA (legacy OMS) | Auto-suffixed by type | `ScriptName_s`, `MetricValue_d` |
| AMA + DCR transform | Name from `transformKql` projection | `ScriptName`, `MetricValue` |

---

### `arg_max` result naming

Do **not** assign `arg_max` to a named variable when you want to access the payload column directly:

```kql
// WRONG – LastState receives the key value (datetime), not a bag
| summarize LastState = arg_max(TimeGenerated, ServiceState)
| extend x = LastState.ServiceState   -- ERROR: path expression on datetime

// CORRECT – arg_max promotes ServiceState as a direct column
| summarize arg_max(TimeGenerated, ServiceState)
| extend x = ServiceState             -- OK
```

---

### Active Alerts panel — Azure Resource Graph

The **Active SQL Monitor Alerts** panel uses `queryType: 1` (Azure Resource Graph). ARG projects `properties.*` as `dynamic` type. The `sort by` operator requires explicit type casts — sorting on `dynamic` causes a runtime error:

```kql
// All projected columns must be explicitly cast
| project
    AlertName = tostring(properties.essentials.alertRule),
    FiredTime = todatetime(properties.essentials.startDateTime),
    Severity  = tostring(properties.essentials.severity)
| sort by FiredTime desc
```

---

### Database Health Status — color thresholds

The `db-status-table` panel uses formatter type 18 (threshold colors) on the `Status` column. The script can return the following status values:

| Status value | Color | Meaning |
|---|---|---|
| `ONLINE` / `Online` | 🟢 Green | Database is online |
| `OK` | 🟢 Green | No user databases found (`NoDatabases`) — healthy state |
| `Unknown` | 🟡 Yellow | Script failed to query the instance (`QueryFailed`) |
| Everything else (`OFFLINE`, `SUSPECT`, etc.) | 🔴 Red | Degraded state |

`OK` is returned by the script when the instance has no user databases — this is not an error. It must be explicitly mapped to green; otherwise it falls through to the default red threshold.

---

### Workbook `sourceId` — Azure Monitor gallery visibility

The workbook resource has a `sourceId` property that controls where it appears in the portal:

| `sourceId` value | Gallery location |
|---|---|
| LAW resource ID | Only in the LAW's own **Workbooks** blade |
| `'Azure Monitor'` | Global **Azure Monitor → Workbooks** gallery ✅ |

The `modules/workbook.bicep` uses `sourceId: 'Azure Monitor'` so the dashboard is discoverable from the Azure Monitor hub, not just the Log Analytics workspace blade. Query execution is not affected — the workspace is embedded inside each KQL panel's `resourceType` configuration.

---

## Gap Analysis

The following SCOM features **cannot be directly replicated** in Azure Monitor, along with recommended Azure-native alternatives.

### 1. Auto-Resolution / Recovery Tasks
- **SCOM capability:** Monitors can trigger recovery tasks (e.g., restart a service, kill a blocking session) automatically upon alert.
- **Azure Monitor gap:** Alert rules fire notifications only; no built-in remediation.
- **Recommendation:** Use **Azure Automation Runbooks** triggered by Azure Monitor alerts via Action Groups (Automation action type). Create runbooks to restart SQL Server services or kill blocking sessions.

### 2. Dependency / Rollup Monitors
- **SCOM capability:** Hierarchical health roll-up (Database → Filegroup → DB Engine → Server). Parent health degrades automatically when child is unhealthy.
- **Azure Monitor gap:** No native health rollup hierarchy. Each alert is independent.
- **Recommendation:** Use **Azure Workbooks** with aggregated health scores (KQL with `summarize`). For service-level views, use **Azure Monitor Resource Health** or **Azure Service Health**.

### 3. Distributed Application Model (DA)
- **SCOM capability:** SQL Server instance health modeled as a distributed application with sub-components.
- **Azure Monitor gap:** No equivalent distributed application view.
- **Recommendation:** Implement a custom **Azure Monitor Workbook** with tabs per component (as provided in `sql-workbook.json`). For full CMDB-like topology, integrate with **Azure Service Map** or **Microsoft Sentinel** entity graphs.

### 4. Management Pack Overrides (per-object configuration)
- **SCOM capability:** Override monitor thresholds per SQL instance or per database without redeploying.
- **Azure Monitor gap:** Alert rules have fixed thresholds. Dynamic per-resource thresholds require separate rules.
- **Recommendation:** Use **Azure Monitor Dynamic Thresholds** (ML-based) for metric-style counters. For event-based rules, parameterize PowerShell scripts via Scheduled Task arguments, stored in an **Azure App Configuration** or **Key Vault** for centralized override management.

### 5. Script-based Action / Diagnostic Tasks
- **SCOM capability:** Right-click on an alert → run diagnostic task (e.g., collect DBCC output, query DMVs).
- **Azure Monitor gap:** No equivalent interactive diagnostic task from the Azure portal.
- **Recommendation:** Use **Azure Automation Runbooks** or **Azure Arc Run Command** to execute diagnostic scripts on demand. Surface results in **Azure Monitor Workbooks** via custom log queries.

### 6. Maintenance Window Suppression
- **SCOM capability:** Define maintenance windows to suppress alerts during planned downtime.
- **Azure Monitor gap:** Azure Monitor has no native maintenance window concept for suppressing alerts.
- **Recommendation:** Use **Alert Processing Rules** (formerly Action Rules) with time-window-based suppression. Schedule via Azure Automation to enable/disable processing rules.

### 7. Agentless Monitoring (Network Device / SNMP)
- **SCOM capability:** Monitors network devices reachable from SCOM management servers without an agent.
- **Azure Monitor gap:** AMA requires a Windows/Linux agent on the monitored host.
- **Recommendation:** Use **Azure Network Watcher Connection Monitor** for connectivity checks. Use **Azure Monitor Synthetic Monitoring** for endpoint availability.

### 8. Cross-Instance Database Replica Monitoring (SCOM Agent Proxy)
- **SCOM capability:** A single SCOM agent can monitor all replicas visible through the primary, including replicas on other servers.
- **Azure Monitor gap:** AMA collects from the local host only.
- **Recommendation:** Install AMA on every AG replica host. Use the `SQLMonitoring_CL` table to correlate results by `AGName` across hosts in the workbook.

### 9. In-Memory OLTP / XTP Monitors
- **SCOM capability:** Dedicated XTP performance monitors (hash index empty buckets, row chains, memory stale checkpoints).
- **Azure Monitor gap:** No built-in XTP counter templates; manual counter specification required.
- **Recommendation:** Add the XTP performance counters (e.g., `\SQLServer:XTP Cursors(*)\*`, `\SQLServer:XTP Storage(*)\*`) to the DCR. Alert rules can be added to `modules/alert-rules.bicep` following the same pattern.

### 10. SSIS Package Monitoring (Detailed Execution Metrics)
- **SCOM capability:** Tracks rows read/written, buffers spooled per SSIS execution in the SCOM performance view.
- **Azure Monitor gap:** Partial — SSIS IS performance counters can be collected, but package-level detail requires SSISDB or Event Log parsing.
- **Recommendation:** Enable **SSIS Integration Runtime logging** to Azure Monitor Logs if using Azure Data Factory. For on-premises SSIS, collect the IS performance counters via the DCR and query `Perf` for rows read/written.

---

## Handling Non-Default (Named) SQL Server Instances

This solution is structured around the default instance (`MSSQLSERVER`) but is designed so that **you do not need a full redeployment** to cover named instances. Each component has a different scope, so the required additions vary. Below is the complete guidance per component.

---

### Component 1 – DCR Performance Counters

**Problem:** Windows performance counter object names are instance-specific. The default instance uses the prefix `SQLServer:`, while named instances use `MSSQL$<INSTANCENAME>:`.

| Instance | Counter path example |
|---|---|
| Default (`MSSQLSERVER`) | `\SQLServer:SQL Statistics\SQL Compilations/sec` |
| Named (`SQL2019`) | `\MSSQL$SQL2019:SQL Statistics\SQL Compilations/sec` |

**Solution:** Add a parallel block of counter paths inside the existing `modules/dcr.bicep`, duplicating all `SQLServer:*` entries with the appropriate `MSSQL$<INSTANCENAME>:*` prefix. The same DCR can then be associated with all machines regardless of instance name.

Example additions in `dcr.bicep` `counterSpecifiers` array:
```
'\\MSSQL$SQL2019:SQL Statistics\\SQL Compilations/sec'
'\\MSSQL$SQL2019:Buffer Manager\\Buffer cache hit ratio'
'\\MSSQL$SQL2019:General Statistics\\Processes Blocked'
'\\MSSQL$SQL2019:Memory Manager\\Total Server Memory (KB)'
'\\MSSQL$SQL2019:Databases(*)\\Transactions/sec'
'\\MSSQL$SQL2019:Locks(_Total)\\Number of Deadlocks/sec'
'\\MSSQL$SQL2019:Availability Replica(*)\\Bytes Sent to Replica/sec'
'\\MSSQL$SQL2019:Database Replica(*)\\Transaction Delay'
```

> One DCR can hold counters for multiple instance prefixes simultaneously. No new DCR deployment or association is needed.

---

### Component 2 – DCR Windows Event Logs

**No changes needed.** All SQL Server instances — default and named — write to the same Windows **Application** Event Log under the `MSSQLSERVER` source name. The XPath filters in the DCR capture events from all instances on the host without modification.

---

### Component 3 – Alert Rules (service-state alerts)

**Problem:** The `sqlServiceName` parameter in `main.bicep` drives alerts like `alert-sql-service-down` and `alert-sqlagent-service-down`. These look for a specific service name in the SCM event log. Named instances have different service names:

| Instance | SQL Engine service | SQL Agent service |
|---|---|---|
| Default | `MSSQLSERVER` | `SQLSERVERAGENT` |
| Named (`SQL2019`) | `MSSQL$SQL2019` | `SQLAgent$SQL2019` |

**Solution options:**

**Option A – Additional alert rules in the same deployment.** Add extra `scheduledQueryRules` resources to `modules/alert-rules.bicep`, one per named instance, using the appropriate service name string in the KQL `has` filter. No new Bicep deployment is needed — just update and redeploy the existing stack.

**Option B – Separate deployment with a different `sqlServiceName` parameter.** Run `az deployment group create` again with a different parameter file pointing to the named instance service name. The alert rule names must be unique, so prefix them accordingly (e.g., `alert-sql2019-service-down`).

> Event-based and script-based alert rules (`SQLMonitoring_CL` queries) are **already multi-instance** — they filter on the `InstanceName` field written by the PowerShell scripts, so a single alert rule fires for any instance that reports a problem.

---

### Component 4 – PowerShell Scripts

**No script changes needed.** All four scripts accept `-InstanceName` and `-AgentInstanceName` parameters and write the instance label into every log line. To monitor a named instance, register additional Scheduled Tasks on the host pointing to the same `.ps1` files with different arguments.

Example for a named instance `SQL2019` on the same host:

```powershell
$namedInstance = 'SQL2019'
$tasks = @(
    @{
        TaskName   = "SQLMonitor-ServiceHealth-$namedInstance"
        Script     = "C:\SQLMonitoring\Scripts\Test-SQLServiceHealth.ps1"
        Arguments  = "-InstanceName `"MSSQL`$$namedInstance`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-AgentJobStatus-$namedInstance"
        Script     = "C:\SQLMonitoring\Scripts\Test-SQLAgentJobStatus.ps1"
        Arguments  = "-InstanceName `"localhost\$namedInstance`" -AgentInstanceName `"MSSQL`$$namedInstance`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-AvailabilityGroup-$namedInstance"
        Script     = "C:\SQLMonitoring\Scripts\Test-SQLAvailabilityGroup.ps1"
        Arguments  = "-InstanceName `"localhost\$namedInstance`" -AgentInstanceName `"MSSQL`$$namedInstance`""
        RepeatMins = 5
    },
    @{
        TaskName   = "SQLMonitor-DatabaseHealth-$namedInstance"
        Script     = "C:\SQLMonitoring\Scripts\Test-SQLDatabaseHealth.ps1"
        Arguments  = "-InstanceName `"localhost\$namedInstance`" -AgentInstanceName `"MSSQL`$$namedInstance`""
        RepeatMins = 10
    }
)

foreach ($task in $tasks) {
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$($task.Script)`" $($task.Arguments)"
    $trigger   = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes $task.RepeatMins) -Once -At (Get-Date)
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $task.TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal -Force
    Write-Host "Registered: $($task.TaskName)"
}
```

> The `-InstanceName` for SQL connection uses `localhost\SQL2019` (backslash notation).
> The `-AgentInstanceName` label uses `MSSQL$SQL2019` (dollar-sign notation, matching the Windows service name).

---

### Component 5 – Workbook

**No changes needed.** The workbook filters data by `Computer` and `InstanceName` fields, both of which are populated dynamically from the ingested data. Once the scripts and DCR counters are producing data for the named instance, it appears automatically in all workbook panels.

---

### Summary – What to add per named instance

| Component | Change required | Scope |
|---|---|---|
| DCR – Perf Counters | Add `MSSQL$NAME:*` counter paths | Edit `modules/dcr.bicep`, redeploy once |
| DCR – Event Logs | Nothing | Already multi-instance |
| DCR – Custom Logs | Nothing | Script writes `InstanceName=` field |
| Alert rules – service state | Add extra alert rules per instance | Edit `modules/alert-rules.bicep` or new deployment |
| Alert rules – event/script-based | Nothing | Already multi-instance via `InstanceName` field |
| PowerShell scripts | Nothing | Parameterized |
| Scheduled Tasks | Register new task set per instance | Run on each host |
| Workbook | Nothing | Dynamic filter on `InstanceName` |
