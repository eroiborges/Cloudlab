# Certificate Health Monitoring – Azure Monitor
## Windows PKI / TLS Certificate Expiry and Chain Validity

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Deployment Instructions](#deployment-instructions)
5. [Agent Configuration Steps](#agent-configuration-steps)
6. [Scheduled Task Setup](#scheduled-task-setup)
7. [Workbook Notes](#workbook-notes)
8. [Alert Rules Reference](#alert-rules-reference)
9. [Gap Analysis](#gap-analysis)

---

## Overview

This solution provides **proactive certificate expiry and chain validation monitoring** for Windows servers using **Azure Monitor**. A single PowerShell collector (`certcollect.ps1`) inspects certificates from multiple sources on each VM, writes structured log output picked up by the Azure Monitor Agent (AMA), and surfaces results in a Log Analytics Workspace with alert rules and a workbook dashboard.

### Certificate sources covered

| Source | What is checked |
|---|---|
| `CertStore` | `Cert:\LocalMachine\My` + `WebHosting` stores — service/web certificates |
| `CertStore (CA)` | `Cert:\LocalMachine\CA` — intermediate CA certificates |
| `IIS` | HTTPS bindings on all IIS sites (requires WebAdministration module) |
| `RDP` | Remote Desktop Services TLS certificate |
| `WinRM` | WinRM HTTPS listener certificate |
| `SQLServer` | Per-instance SSL/TLS certificate (from registry, all instances) |

### What the template creates

This is a **self-contained deployment** — no pre-existing Log Analytics Workspace or Action Group is required.

| Resource | Type | Notes |
|---|---|---|
| Log Analytics Workspace | `Microsoft.OperationalInsights/workspaces` | Created with PerGB2018 SKU, configurable retention |
| `CertHealth_CL` table | `Microsoft.OperationalInsights/workspaces/tables` | Custom log table; created before DCR and alerts |
| Action Group | `Microsoft.Insights/actionGroups` | Email receiver; `location: global` |
| Data Collection Rule | `Microsoft.Insights/dataCollectionRules` | Tails `CertHealth.log` and transforms to `CertHealth_CL` |
| 6 Scheduled Query Rules | `Microsoft.Insights/scheduledQueryRules` | Alert rules for expiry, chain, IIS, CA, and collection errors |
| Certificate Health Workbook | `Microsoft.Insights/workbooks` | Dashboard with summary tiles, inventory grid, and active issues |

### Artifact Reference

| Artifact | Path | Purpose |
|---|---|---|
| `main.bicep` | `./main.bicep` | Orchestrates all resources including LAW and Action Group |
| `modules/dcr.bicep` | `./modules/dcr.bicep` | Data Collection Rule (custom log ingestion + KQL transform) |
| `modules/alert-rules.bicep` | `./modules/alert-rules.bicep` | 6 Azure Monitor Scheduled Query Rules |
| `modules/workbook.bicep` | `./modules/workbook.bicep` | Workbook deployment wrapper |
| `workbook/cert-workbook.json` | `./workbook/cert-workbook.json` | Certificate Health Dashboard (expiry tiles, inventory, active issues) |
| `scripts/certcollect.ps1` | `./scripts/` | Main certificate collector (all 5 sources, writes CertHealth.log) |
| `scripts/Install-CertMonitor.ps1` | `./scripts/` | One-shot VM setup: directories, file copy, event source, scheduled task |
| `scripts/Invoke-CertMonitorLogRotation.ps1` | `./scripts/` | Log file rotation and purge (run daily) |

---

## Architecture

```
Windows VM (Azure Arc-enabled or Azure VM)
  │
  ├─ Azure Monitor Agent (AMA)
  │    └─ Custom Log DCR
  │         └─ Tails: C:\WindowsAzure\Certs\logs\CertHealth.log
  │              └─ KQL transform → CertHealth_CL (Log Analytics)
  │
  └─ Scheduled Task (certcollect.ps1, daily / configurable interval)
       │
       ├─ CertStore  : Cert:\LocalMachine\My + WebHosting
       ├─ CertStore  : Cert:\LocalMachine\CA  (intermediate CAs)
       ├─ IIS        : HTTPS site bindings
       ├─ RDP        : Remote Desktop TLS certificate
       ├─ WinRM      : WinRM HTTPS listener
       └─ SQLServer  : Per-instance SSL/TLS certificate (registry)
            │
            └─ Writes key=value rows → C:\WindowsAzure\Certs\logs\CertHealth.log
                                              ↑ ingested by AMA custom log DCR

Azure Monitor / Log Analytics Workspace
  └─ CertHealth_CL  (parsed certcollect output via DCR KQL transform)
       │
       ├─ 6 Scheduled Query Rules (Alert Rules)
       └─ Certificate Health Workbook Dashboard
```

---

## Prerequisites

### Azure-side
- Contributor + Monitoring Contributor RBAC on the target Resource Group
- The Log Analytics Workspace, `CertHealth_CL` table, Action Group, DCR, alert rules, and workbook are **all created by this template** — no pre-existing resources required

### VM Hosts
- Windows Server 2016 or later
- **Azure Monitor Agent (AMA)** installed (replaces the legacy MMA/OMS agent)
  - Install via Azure Arc for on-premises servers
  - Minimum version: AMA 1.10+
- PowerShell 5.1 or later
- Local Administrator rights to run `Install-CertMonitor.ps1`
- No special SQL Server or Active Directory permissions required

> **IIS source:** If `certcollect.ps1` is run with `-Source IIS` (or with all sources, which includes IIS), the `WebAdministration` PowerShell module must be available on the VM. This module ships with IIS and is present on any host where IIS is installed.

---

## Deployment Instructions

### Step 1 – Clone / Copy artifacts

Copy this `CertMonitor/` folder to your deployment workstation.

### Step 2 – Set parameter values

Edit `parameters.json` with your values. All resources are created by the template:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceName": {
      "value": "law-certmonitor-prod"
    },
    "workspaceRetentionDays": {
      "value": 30
    },
    "actionGroupName": {
      "value": "ag-cert-monitor"
    },
    "actionGroupShortName": {
      "value": "CertAlert"
    },
    "alertEmailAddress": {
      "value": "ops-team@contoso.com"
    },
    "logFilePath": {
      "value": "C:\\WindowsAzure\\Certs\\logs\\CertHealth.log"
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
| `actionGroupName` | Action Group resource name | `ag-cert-monitor` |
| `actionGroupShortName` | Display short name (max 12 chars) | `CertAlert` |
| `alertEmailAddress` | Email address to receive alert notifications | _(required)_ |
| `logFilePath` | Full path to `CertHealth.log` on monitored VMs | `C:\WindowsAzure\Certs\logs\CertHealth.log` |
| `environment` | Tag value | `production` |
| `ownerTag` | Tag value | `IT-Operations` |

> **Note on `logFilePath`:** This value must match the path used by `certcollect.ps1` on the VMs (the `-MonitoringFolder` parameter). The default `C:\WindowsAzure\Certs\logs\` follows the Azure Arc agent convention for custom extensions.

> **Note on Action Group location:** Action Groups always deploy to `global` in Azure Monitor regardless of the resource group region — this is the correct and expected behavior.

### Step 3 – Deploy via Azure CLI

```bash
# Set variables
monitorrg="<YOUR_RESOURCE_GROUP for Monitor Artifacts>"
arcrg="<YOUR_RESOURCE_GROUP where Arc VMs are>"
sub="<YOUR_SUBSCRIPTION_ID>"
deployname="CertMonitorDeploy-$(date +%Y%m%d)"

# Login and set subscription
az login
az account set --subscription "$sub"

# Deploy Monitor artifacts
az deployment group create \
  --resource-group "$monitorrg" \
  --template-file main.bicep \
  --parameters @parameters.json \
  --name "$deployname"
```

### Step 4 – Associate DCR with monitored machines

After deployment, associate the DCR with each Arc-enabled (or Azure) VM:

```bash
# $monitorrg, $arcrg and $deployname defined in Step 3
machines=("<MACHINE_NAME_1>" "<MACHINE_NAME_2>")   # add one entry per Arc-enabled VM

# Get the DCR Resource ID from the deployment output
DCR_ID=$(az deployment group show \
  --resource-group "$monitorrg" \
  --name "$deployname" \
  --query "properties.outputs.dcrResourceId.value" -o tsv)

# Associate the DCR with each Arc machine
for machinename in "${machines[@]}"; do
  arcvmid=$(az connectedmachine show --name "$machinename" --resource-group "$arcrg" --query id -o tsv)
  az monitor data-collection rule association create \
    --name "CertHealth-DCR-Association" \
    --resource "$arcvmid" \
    --rule-id "$DCR_ID"
  echo "Associated DCR with: $machinename"
done
```

> For **Azure VMs** (not Arc), replace `az connectedmachine show` with `az vm show --resource-group "$arcrg" --name "$machinename" --query id -o tsv`.

### Step 5 – Custom log table

The `CertHealth_CL` table is **automatically created by this template** with the correct schema before the DCR and alert rules deploy. No manual step required.

---

## Agent Configuration Steps

### 1. Install Azure Monitor Agent

**Azure Arc-enabled servers (on-premises):**
```bash
# Set machine-specific variables
machinename="<YOUR_ARC_MACHINE_NAME>"
arcrg="<YOUR_ARC_RESOURCE_GROUP>"
location="<YOUR_LOCATION>"   # e.g. eastus

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
vmname="<YOUR_VM_NAME>"
vmrg="<YOUR_VM_RESOURCE_GROUP>"

az vm extension set \
  --resource-group "$vmrg" \
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

---

## Scheduled Task Setup

`Install-CertMonitor.ps1` performs the entire VM-side setup in one step:

1. Creates `C:\WindowsAzure\Certs\scripts\` and `C:\WindowsAzure\Certs\logs\`
2. Copies `certcollect.ps1` to `C:\WindowsAzure\Certs\scripts\certcollect.ps1`
3. Registers the Windows Application Event Log source (`ADMonitoringScript`)
4. Creates the Scheduled Task (`CertMonitor-CertCollect`) running as `SYSTEM`
5. **Fires the first execution immediately** so data appears without waiting for the repeat interval
6. By default, copies `Invoke-CertMonitorLogRotation.ps1` and registers `CertMonitor-LogRotation` (daily at 02:00)

Run on each VM with local Administrator rights:

```powershell
# Copy both scripts to C:\temp\ (or any local folder) then run:
.\Install-CertMonitor.ps1
```

### Default parameters

| Parameter | Default | Description |
|---|---|---|
| `-ScriptSourcePath` | `.\certcollect.ps1` | Source PS1 to deploy (sibling file) |
| `-ScriptInstallPath` | `C:\WindowsAzure\Certs\scripts\certcollect.ps1` | Destination on VM |
| `-MonitoringFolder` | `C:\WindowsAzure\Certs\logs` | Where CertHealth.log is written |
| `-UploadMode` | `DCR` | `DCR` (AMA file pickup) or `Metrics` (REST API via Managed Identity) |
| `-TaskName` | `CertMonitor-CertCollect` | Task Scheduler job name |
| `-IntervalMinutes` | `1440` | Run frequency (1440 = once per day) |
| `-RunAsUser` | _(none — runs as SYSTEM)_ | Identity for the scheduled task (domain account, gMSA, or local account). See [Service Account – Least-Privilege Setup](#service-account--least-privilege-setup) for the required permissions and account creation steps before using this parameter. |
| `-RunAsPassword` | _(prompted if needed)_ | Optional SecureString password for `-RunAsUser` when using a non-gMSA account. If omitted, the script prompts once and reuses the same credential for both tasks. |
| `-LogRotation` | `$true` | Enables automatic copy of `Invoke-CertMonitorLogRotation.ps1` and registration of the daily log rotation task. |
| `-LogRotationSourcePath` | `./Invoke-CertMonitorLogRotation.ps1` | Optional source path for the log rotation script (defaults to sibling file next to installer). |
| `-LogRotationTaskName` | `CertMonitor-LogRotation` | Task name used for the log rotation schedule. |
| `-Force` | `$false` | Overwrite existing task |

> **Security note:** By default the task runs as `SYSTEM`, which satisfies all permission requirements but grants unrestricted OS access. For environments governed by CIS, STIG, or internal hardening baselines, use `-RunAsUser` with a dedicated low-privilege account. **Read the [Service Account – Least-Privilege Setup](#service-account--least-privilege-setup) section in full before choosing an identity** — it covers gMSA, local, and domain account options with the exact ACLs and local rights each one requires.

### Override examples

```powershell
# Run every 60 minutes instead of daily
.\Install-CertMonitor.ps1 -IntervalMinutes 60

# Deploy from a network share
.\Install-CertMonitor.ps1 -ScriptSourcePath '\\fileserver\deploy\certcollect.ps1'

# Use Metrics upload mode (requires Managed Identity on the VM)
.\Install-CertMonitor.ps1 -UploadMode Metrics

# Re-register an existing task (force overwrite)
.\Install-CertMonitor.ps1 -Force

# Disable automatic log rotation setup
.\Install-CertMonitor.ps1 -LogRotation $false

# Provide explicit log rotation source path
.\Install-CertMonitor.ps1 -LogRotationSourcePath 'C:\temp\Invoke-CertMonitorLogRotation.ps1'

# Use a custom log rotation task name
.\Install-CertMonitor.ps1 -LogRotationTaskName 'CertMonitor-LogRotation-Prod'

# Run as a domain service account (password will be prompted securely)
.\Install-CertMonitor.ps1 -RunAsUser 'DOMAIN\svc-certmonitor'

# Run as a domain service account with an explicit SecureString password
$pwd = Read-Host -AsSecureString 'svc-certmonitor password'
.\Install-CertMonitor.ps1 -RunAsUser 'DOMAIN\svc-certmonitor' -RunAsPassword $pwd

# Run as a Group Managed Service Account (no password required — $ suffix detected automatically)
.\Install-CertMonitor.ps1 -RunAsUser 'DOMAIN\svc-certmonitor$'
```

### Verify log file

After the first run (triggered automatically by `Install-CertMonitor.ps1`):

```powershell
Get-Item "C:\WindowsAzure\Certs\logs\CertHealth.log" | Select-Object Name, LastWriteTime, Length
# Expected: file present with a recent LastWriteTime

# Preview first few rows
Get-Content "C:\WindowsAzure\Certs\logs\CertHealth.log" -Head 20
```

If the file is missing or empty, check the Windows Application Event Log for errors:

```powershell
Get-EventLog -LogName Application -Source ADMonitoringScript -Newest 20 |
    Select-Object TimeGenerated, EntryType, Message |
    Format-List
```

### Log rotation

Register the log rotation task (run daily at 02:00 AM). Run once per VM with local Administrator rights.

> `Install-CertMonitor.ps1` already configures log rotation by default (`-LogRotation $true`). Use the manual registration examples below only when you choose to manage the log-rotation task yourself.

> **Least-privilege:** Use the **same `svc-certmonitor` service account** as the collector task. `Invoke-CertMonitorLogRotation.ps1` only reads, renames, and deletes files under `C:\WindowsAzure\Certs\logs\` — fully covered by the **Modify** ACL already granted. No additional permissions are required. Use `RunLevel Limited` (not `Highest`) for a standard user account.

**Option A — gMSA (domain-joined):**

```powershell
$ScriptDir   = "C:\WindowsAzure\Certs\scripts"
$action      = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-CertMonitorLogRotation.ps1`""
$trigger     = New-ScheduledTaskTrigger -Daily -At "02:00"
$settings    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable
$principal   = New-ScheduledTaskPrincipal -UserId "DOMAIN\svc-certmonitor$" -LogonType Password -RunLevel Limited

Register-ScheduledTask -TaskName "CertMonitor-LogRotation" `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
Write-Host "Registered: CertMonitor-LogRotation"
```

**Option B — local account (standalone / workgroup):**

```powershell
$ScriptDir   = "C:\WindowsAzure\Certs\scripts"
$action      = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Invoke-CertMonitorLogRotation.ps1`""
$trigger     = New-ScheduledTaskTrigger -Daily -At "02:00"
$settings    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable
$principal   = New-ScheduledTaskPrincipal -UserId ".\svc-certmonitor" -LogonType Password -RunLevel Limited
$password    = Read-Host "svc-certmonitor password"   # plain string required by Register-ScheduledTask

Register-ScheduledTask -TaskName "CertMonitor-LogRotation" `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Password $password -Force
Write-Host "Registered: CertMonitor-LogRotation"
```

> **How rotation works with AMA:** AMA tracks the last read position (byte offset) per file. When a log file is rotated (renamed), AMA treats the new empty file as a fresh source — no duplicate ingestion.

---

## Service Account – Least-Privilege Setup

Running the scheduled task as `SYSTEM` grants full OS access and is flagged by most security benchmarks (CIS, STIG). The table below maps each operation `certcollect.ps1` performs to the **minimum** Windows right or ACL required, so you can create a dedicated low-privilege account.

### Permission matrix

| Source / Operation | Resource accessed | Minimum right | Default for Users? |
|---|---|---|---|
| All sources | Write `CertHealth.log`, `CertMetricLog.csv` | **Modify** ACL on `C:\WindowsAzure\Certs\logs\` | No — must be granted |
| All sources | Read `certcollect.ps1` | **ReadAndExecute** ACL on `C:\WindowsAzure\Certs\scripts\` | No — must be granted |
| All sources | Write to Application Event Log | Write to pre-existing `ADMonitoringScript` source | **Yes** — standard users can write to existing sources |
| Scheduled Task | Logon type for a batch job | `Log on as a batch job` (`SeBatchLogonRight`) | No — must be assigned via Local Security Policy or GPO |
| `CertStore` | `Get-ChildItem Cert:\LocalMachine\My` / `WebHosting` / `CA` | Read certificate **public metadata** only (not private key) | **Yes** — Users group has read on LocalMachine stores by default |
| `IIS` | `Get-ChildItem IIS:\SslBindings` | Member of **`IIS_IUSRS`** built-in local group | No — must be added |
| `RDP` | `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp` | Read — Users group has read on this key by default | **Yes** |
| `WinRM` | `WSMan:\localhost\Listener\*` | Member of **`Remote Management Users`** built-in local group | No — must be added |
| `SQLServer` | `HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\*\MSSQLServer\SuperSocketNetLib` | Explicit **Read** on registry key — SQL Server restricts this to Administrators by default | No — must be granted |

> **Private keys are never accessed.** `certcollect.ps1` reads only certificate public properties (`NotAfter`, `Thumbprint`, `Subject`, `Issuer`) and builds the chain via `X509Chain.Build()` — no private key operations.

---

### Step 1 — Create the service account

**Option A: Group Managed Service Account (gMSA) — recommended for domain environments**

gMSA passwords are managed automatically by Active Directory — no password to store, rotate, or expire.

```powershell
# Run on a domain controller (requires AD PowerShell module + KDS root key)
New-ADServiceAccount `
    -Name               'svc-certmonitor' `
    -DNSHostName        'svc-certmonitor.DOMAIN.LOCAL' `
    -PrincipalsAllowedToRetrieveManagedPassword (Get-ADComputer '<TARGETVM>') `
    -Enabled            $true

# Install on the target VM (run on the VM itself or via remote PS)
Install-ADServiceAccount -Identity 'svc-certmonitor$'
```

Use `-RunAsUser 'DOMAIN\svc-certmonitor$'` with `Install-CertMonitor.ps1` — Task Scheduler recognises the `$` suffix and does not require a password.

**Option B: Local account — for standalone / workgroup servers**

```powershell
# Run on the target VM with local Administrator rights
$pwd = Read-Host -AsSecureString 'Service account password'
New-LocalUser -Name              'svc-certmonitor' `
              -Password           $pwd `
              -PasswordNeverExpires $true `
              -UserMayNotChangePassword $true `
              -Description        'CertMonitor scheduled task account'
```

**Option C: Domain account — without gMSA**

```powershell
# Run on a domain controller or with RSAT
New-ADUser `
    -Name               'svc-certmonitor' `
    -SamAccountName     'svc-certmonitor' `
    -AccountPassword    (Read-Host -AsSecureString 'Password') `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled            $true
```

---

### Step 2 — Grant the required Windows rights

Run the following block on **each monitored VM** with local Administrator rights. Adjust `$account` to match your choice from Step 1.

```powershell
$account = 'HOSTNAME\svc-certmonitor'    # local account — replace HOSTNAME
# $account = 'DOMAIN\svc-certmonitor'   # domain account
# $account = 'DOMAIN\svc-certmonitor$'  # gMSA

# ── File system ────────────────────────────────────────────────────────────
$scriptsDir = 'C:\WindowsAzure\Certs\scripts'
$logsDir    = 'C:\WindowsAzure\Certs\logs'

foreach ($dir in @($scriptsDir, $logsDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $acl  = Get-Acl $dir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $account,
        $(if ($dir -eq $logsDir) { 'Modify' } else { 'ReadAndExecute' }),
        'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl $dir $acl
    Write-Host "ACL set on: $dir"
}

# ── Log on as a batch job (SeBatchLogonRight) ─────────────────────────────
$sid     = (New-Object System.Security.Principal.NTAccount($account)).Translate(
               [System.Security.Principal.SecurityIdentifier]).Value
$tmpFile = [IO.Path]::GetTempFileName()
secedit /export /cfg $tmpFile /quiet
$cfg = (Get-Content $tmpFile) -replace `
    '(SeBatchLogonRight\s*=\s*)(.*)', "`$1`$2,*$sid"
Set-Content $tmpFile $cfg
secedit /configure /cfg $tmpFile /db secedit.sdb /quiet
Remove-Item $tmpFile -Force
Write-Host "SeBatchLogonRight granted to $account"

# ── Built-in group memberships ────────────────────────────────────────────
# IIS source — read IIS SSL bindings
Add-LocalGroupMember -Group 'IIS_IUSRS'               -Member $account -ErrorAction SilentlyContinue

# WinRM source — enumerate WS-Man listeners
Add-LocalGroupMember -Group 'Remote Management Users' -Member $account -ErrorAction SilentlyContinue

Write-Host "Group memberships granted."

# ── SQL Server registry key (SQLServer source) ────────────────────────────
$sqlRoot = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
if (Test-Path $sqlRoot) {
    $acl  = Get-Acl $sqlRoot
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $account, 'ReadKey', 'ContainerInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl $sqlRoot $acl
    Write-Host "Registry read granted on: $sqlRoot"
}
```

> **GPO alternative for `SeBatchLogonRight`:** Navigate to `Computer Configuration → Windows Settings → Security Settings → Local Policies → User Rights Assignment → Log on as a batch job` and add the account. This is the preferred approach for domain-joined VMs.

---

### Step 3 — Install with the service account

```powershell
# Local account
.\Install-CertMonitor.ps1 -RunAsUser "$env:COMPUTERNAME\svc-certmonitor"

# Domain account (prompts for password)
.\Install-CertMonitor.ps1 -RunAsUser "DOMAIN\svc-certmonitor"

# gMSA — no password prompt
.\Install-CertMonitor.ps1 -RunAsUser "DOMAIN\svc-certmonitor$"
```

### Step 4 — Pre-create the Event Log source (one-time, as Administrator)

The `ADMonitoringScript` source must be created by an admin before the service account can write to it:

```powershell
# Run once per VM with local Administrator rights
if (-not [System.Diagnostics.EventLog]::SourceExists('ADMonitoringScript')) {
    [System.Diagnostics.EventLog]::CreateEventSource('ADMonitoringScript', 'Application')
    Write-Host "Event source 'ADMonitoringScript' created."
} else {
    Write-Host "Event source already exists."
}
```

`Install-CertMonitor.ps1` does this automatically in Step 3 of its setup flow — no manual action needed if you run it as Administrator.

### Permission summary

| Scope | Object / Right | Purpose |
|---|---|---|
| File system | **ReadAndExecute** on `C:\WindowsAzure\Certs\scripts\` | Execute certcollect.ps1 |
| File system | **Modify** on `C:\WindowsAzure\Certs\logs\` | Write CertHealth.log + CertMetricLog.csv |
| Local right | `SeBatchLogonRight` | Task Scheduler logon |
| Local group | `IIS_IUSRS` | Read IIS SSL bindings (IIS source) |
| Local group | `Remote Management Users` | Enumerate WS-Man listeners (WinRM source) |
| Registry | **ReadKey** on `HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server` | Read SQL SSL certificate thumbprint (SQLServer source) |
| Event Log | Write to pre-existing `ADMonitoringScript` source | Error/warning events | All users by default once source is created |

---

## Workbook Notes

This section documents design decisions and known behaviors in `workbook/cert-workbook.json`.

---

### Summary tiles — single merged query

The six summary tiles (Expired, Critical ≤30d, Warning ≤60d, Healthy >60d, Chain Broken, Chain Valid) are produced by a **single KQL query** using `countif()` + `mv-expand`:

```kql
CertHealth_CL
| where MetricName == "CertDaysToExpiry" or MetricName == "CertChainValid"
| summarize
    Expired      = countif(MetricName == "CertDaysToExpiry" and toint(Value) <  0),
    Critical     = countif(MetricName == "CertDaysToExpiry" and toint(Value) >= 0 and toint(Value) <= 30),
    Warning      = countif(MetricName == "CertDaysToExpiry" and toint(Value) >  30 and toint(Value) <= 60),
    Healthy      = countif(MetricName == "CertDaysToExpiry" and toint(Value) >  60),
    ChainBroken  = countif(MetricName == "CertChainValid"   and toint(Value) == 0),
    ChainValid   = countif(MetricName == "CertChainValid"   and toint(Value) == 1)
| extend Categories = pack_array("Expired","Critical <=30d","Warning <=60d","Healthy >60d","Chain Broken","Chain Valid")
| extend Counts     = pack_array(Expired, Critical, Warning, Healthy, ChainBroken, ChainValid)
| mv-expand Category = Categories to typeof(string), Count = Counts to typeof(long)
| project Category, Count
```

> **Why `extend` before `mv-expand`:** Using `project pack_array(...)` before `mv-expand` destroys the scalar columns needed by the expansion. Always use `extend` to create the named dynamic arrays, then `mv-expand` against those.

---

### Parameters — `quote:""` and `delimiter:"|"`

The `ServerName`, `SourceCategory`, `Severity`, and `Thumbprint` multi-select parameters use `quote: ""` (empty) and `delimiter: "|"`. This is required because:

- `quote: "'"` causes the template `'{Param}'` to expand to `''value''` (double-quoted) — parse error.
- The KQL filter uses `split()` instead of `in ({Param})` to handle empty selections:

```kql
// Correct pattern — handles empty = all, single value, and multi-select
| where isempty('{ServerName}') or ServerName in~ (split('{ServerName}', '|'))

// WRONG — in () with empty parens is a parse error when nothing is selected
| where ServerName in ({ServerName})
```

---

### `ServerName` derivation

`CertHealth_CL` does not have a dedicated `Computer` field after the DCR transform. `ServerName` is extracted from `_ResourceId` in workbook queries:

```kql
| extend ServerName = extract(@'(?i)/machines/([^/]+)$', 1, _ResourceId)
```

---

### `SourceCategory` derivation

The `Source` field in `CertHealth_CL` contains values like `CertStore:My`, `IIS:Default Web Site`. The `SourceCategory` parameter dropdown groups these by prefix:

```kql
| extend SourceCategory = case(
    Source startswith "CertStore:", "CertStore",
    Source startswith "IIS:",       "IIS",
    Source startswith "SQLServer:", "SQLServer",
    Source startswith "RDP",        "RDP",
    Source startswith "WinRM",      "WinRM",
    "Other")
```

---

### Workbook `sourceId` — Azure Monitor gallery visibility

| `sourceId` value | Gallery location |
|---|---|
| LAW resource ID | Only in the LAW's own **Workbooks** blade |
| `'Azure Monitor'` | Global **Azure Monitor → Workbooks** gallery ✅ |

`modules/workbook.bicep` uses `sourceId: 'Azure Monitor'` so the dashboard is discoverable from the Azure Monitor hub. The workspace ID is injected at deploy time via `replace()` on the `__WORKSPACE_RESOURCE_ID__` placeholder.

---

### Certificate Inventory grid — `arg_max` deduplication

The inventory panel deduplicates certificates so each thumbprint appears once per server (taking the most recent row):

```kql
CertHealth_CL
| where MetricName == "CertDaysToExpiry"
| summarize arg_max(TimeGenerated, *) by Thumbprint, ServerName
```

> Do **not** assign `arg_max` to a named variable when you need to access the promoted columns directly — assigning it returns the key value (datetime), not a bag. Use the unassigned form and reference `Value`, `Subject`, etc. directly.

---

## Alert Rules Reference

| # | Alert Name | Severity | Evaluation | Trigger Condition |
|---|---|---|---|---|
| 1 | `alert-cert-expiry-critical` | 1 (High) | Every 15 min / 48h window | `CurrentDaysToExpiry <= 30` (real-time, computed from latest collection) |
| 2 | `alert-cert-expiry-warning` | 2 (Medium) | Every 1h / 48h window | `CurrentDaysToExpiry > 30 and <= 60` |
| 3 | `alert-cert-chain-broken` | 1 (High) | Every 15 min / 48h window | `MetricName == "CertChainValid"` and `Value == 0` |
| 4 | `alert-ca-cert-expiry` | 1 (High) | Every 1h / 48h window | `CurrentDaysToExpiry <= 7` (CA intermediate cert) |
| 5 | `alert-iis-cert-critical` | 1 (High) | Every 15 min / 48h window | IIS-sourced cert with `CurrentDaysToExpiry <= 30` |
| 6 | `alert-collection-error` | 3 (Low) | Every 30 min / 48h window | `Event in ("Error", "StoreError", "IMDSError", "MetricPushError")` |

> **Collection interval constraint:** Azure Monitor Scheduled Query Rules enforce a maximum look-back of **48 hours** (API limit, not configurable). The alert evaluation window is set to `P2D` (48h). This means the scheduled task on each VM **must run at least once every 48 hours** for alerts to fire reliably. The default `-IntervalMinutes 1440` (24h) satisfies this. If you increase the interval beyond 2880 minutes (48h), collection data will age out of the evaluation window and alerts will not trigger.

### How the alert queries work

All cert-state alert rules (1–5) use the same pattern instead of filtering on the `Severity` value stored at collection time:

```kql
CertHealth_CL
| where MetricName == "CertDaysToExpiry"
| summarize arg_max(TimeGenerated, *) by Thumbprint        // latest record per cert only
| extend CurrentDaysToExpiry = Value - (datetime_diff('minute', now(), TimeGenerated) / 1440.0)
| where CurrentDaysToExpiry <= 30                          // real-time threshold
```

**Why `arg_max` + real-time calculation instead of stored `Severity`:**
- Stored `Severity` is computed at collection time. A cert recorded as "Warning" (35 days) one day ago now has ~34 days remaining — still "Warning" by the stored value, but the real current state should be evaluated against the threshold at query time.
- `arg_max(TimeGenerated, *) by Thumbprint` ensures only the **most recent** collection record per certificate is evaluated, preventing duplicate alert instances from multiple collection runs.
- `CurrentDaysToExpiry` subtracts elapsed time since collection so the threshold comparison always reflects the certificate's actual remaining life.

### Alert dimension splits

All alert rules split on `Source` and `Thumbprint` so each individual certificate fires its own independent alert instance:

```bicep
dimensions: [
  { name: 'Source',     operator: 'Include', values: [ '*' ] }
  { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
]
```

**Why this matters:** Without dimension splits, a single alert fires for the entire workspace scope. When split, the alert title identifies the specific source and certificate thumbprint, and acknowledging one alert does not suppress alerts for other certificates.

---

## Gap Analysis

The following capabilities are **not natively available** in Azure Monitor, with recommended alternatives.

### 1. Auto-Resolution / Renewal Triggering
- **Desired:** Automatically renew or flag a certificate for renewal when an alert fires.
- **Azure Monitor gap:** Alert rules fire notifications only; no built-in remediation.
- **Recommendation:** Use **Azure Automation Runbooks** triggered by Azure Monitor alerts (Automation action type in the Action Group). Runbooks can invoke `certreq`, call ACME/SCEP APIs, or open ITSM tickets via the ServiceNow connector.

### 2. Per-Certificate Health Rollup
- **Desired:** A single health state per host that aggregates across all certificate sources and severities.
- **Azure Monitor gap:** No native health rollup hierarchy. Each alert rule is independent.
- **Recommendation:** Use the **Certificate Health Workbook** summary tiles and the inventory grid as the rollup view. For programmatic rollup, query `CertHealth_CL | summarize worst = min(toint(Value)) by ServerName` and surface via a workbook KQL panel.

### 3. Push Notification on First Expiry Detection
- **Desired:** Alert fires the moment a certificate first falls below a threshold, not just on repeated polling intervals.
- **Azure Monitor gap:** Scheduled Query Rules evaluate on a fixed window and will re-fire on every evaluation period while the condition is true (`autoMitigate: true` suppresses re-fires for the same dimension value after the first alert).
- **Recommendation:** `autoMitigate: true` is set on all alert rules — Azure Monitor automatically resolves the alert when the condition clears (e.g., after certificate renewal), and re-fires on the next violation. This provides effectively stateful alerting.

### 4. Certificate Store Write / Import
- **Desired:** Remediate by automatically importing a renewed certificate into the correct store.
- **Azure Monitor gap:** No built-in store management.
- **Recommendation:** Use **Azure Arc Run Command** (`az connectedmachine run-command create`) to execute a PowerShell snippet that imports the PFX from a Key Vault secret. Trigger via Automation Runbook on alert.

### 5. Maintenance Window Suppression
- **Desired:** Suppress certificate expiry alerts during planned maintenance or renewal windows.
- **Azure Monitor gap:** No native maintenance window concept for suppressing alerts.
- **Recommendation:** Use **Alert Processing Rules** (formerly Action Rules) with time-window-based suppression scoped to the resource group or specific resource. Schedule enable/disable via Azure Automation.

### 6. Certificate Authority Integration
- **Desired:** Cross-reference detected certificates against an internal CA to determine if a replacement has already been issued.
- **Azure Monitor gap:** Azure Monitor has no CA query capability.
- **Recommendation:** Extend `certcollect.ps1` to call `certutil -ping` or query the CA via LDAP, and log the result as an additional metric row in `CertHealth.log`. This data then flows into `CertHealth_CL` via the existing DCR pipeline.
