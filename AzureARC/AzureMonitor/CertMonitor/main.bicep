// =============================================================================
// main.bicep
// Certificate Health Monitoring – Azure Monitor
// Monitors certificate expiry and chain validity across all Windows VM sources:
//   CertStore (My, WebHosting, CA), IIS HTTPS bindings, RDP, WinRM, SQL Server
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the Log Analytics Workspace to create.')
param workspaceName string

@description('Log Analytics Workspace data retention in days (30–730).')
@minValue(30)
@maxValue(730)
param workspaceRetentionDays int = 30

@description('Name for the Action Group that receives alert notifications.')
param actionGroupName string = 'ag-cert-monitor'

@description('Display name for the Action Group (max 12 characters).')
@maxLength(12)
param actionGroupShortName string = 'CertAlert'

@description('Email address to receive certificate monitoring alert notifications.')
param alertEmailAddress string

@description('Full path to CertHealth.log on monitored VMs.')
param logFilePath string = 'C:\\WindowsAzure\\Certs\\logs\\CertHealth.log'

@description('Tag: deployment environment.')
@allowed([ 'production', 'staging', 'development' ])
param environment string = 'production'

@description('Tag: owner team or contact.')
param ownerTag string = 'IT-Operations'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var tags = {
  Environment: environment
  ManagedBy: 'AzureMonitor'
  Solution: 'CertMonitoring'
  Owner: ownerTag
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: workspaceRetentionDays
  }
}

var workspaceResourceId = workspace.id

// ---------------------------------------------------------------------------
// Action Group
// Action Groups always use location 'global' in Azure Monitor.
// ---------------------------------------------------------------------------

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: 'cert-alerts-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

var actionGroupResourceId = actionGroup.id

// ---------------------------------------------------------------------------
// Pre-requisite: CertHealth_CL custom log table
// Must exist before the DCR can reference the custom output stream.
//
// Columns match key=value fields emitted by certcollect.ps1:
//   Source      – CertStore:My | IIS:<site> | RDP | WinRM | SQLServer:<inst>
//   MetricName  – CertDaysToExpiry | CertChainValid | CACertDaysToExpiry
//   Store       – My | WebHosting | CA
//   Thumbprint  – certificate SHA-1 thumbprint
//   Status      – Healthy | Warning | Critical | Expired | Valid | ...
//   Severity    – OK | Warning | Critical | Error
//   Value       – numeric metric value (days remaining, 0/1 flag)
//   Subject     – certificate DN (commas replaced with semicolons)
//   Message     – human-readable description
//   Event       – Start | End | StoreScanned | Error | Skipped | ...
// ---------------------------------------------------------------------------

resource certHealthTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'CertHealth_CL'
  properties: {
    schema: {
      name: 'CertHealth_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'ScriptName',   type: 'string'   }
        { name: 'Source',       type: 'string'   }
        { name: 'MetricName',   type: 'string'   }
        { name: 'Store',        type: 'string'   }
        { name: 'Thumbprint',   type: 'string'   }
        { name: 'Status',       type: 'string'   }
        { name: 'Severity',     type: 'string'   }
        { name: 'Value',        type: 'real'     }
        { name: 'Subject',      type: 'string'   }
        { name: 'Message',      type: 'string'   }
        { name: 'Event',        type: 'string'   }
        { name: 'RawData',      type: 'string'   }
      ]
    }
    // No explicit retention — table inherits workspace default (matches SQLMonitoring_CL pattern)
  }
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module dcr 'modules/dcr.bicep' = {
  name: 'deploy-cert-dcr'
  dependsOn: [ certHealthTable ]
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    logFilePath: logFilePath
    tags: tags
  }
}

module alerts 'modules/alert-rules.bicep' = {
  name: 'deploy-cert-alerts'
  dependsOn: [ certHealthTable ]
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    actionGroupResourceId: actionGroupResourceId
    tags: tags
  }
}

module workbook 'modules/workbook.bicep' = {
  name: 'deploy-cert-workbook'
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Log Analytics workspace.')
output workspaceResourceId string = workspaceResourceId

@description('Log Analytics Workspace ID (GUID) — use for AMA agent configuration.')
output workspaceId string = workspace.properties.customerId

@description('Resource ID of the Data Collection Rule. Associate this with target VMs after deployment.')
output dcrResourceId string = dcr.outputs.dcrResourceId

@description('Name of the DCR.')
output dcrName string = dcr.outputs.dcrName

@description('Resource ID of the Certificate Health Workbook.')
output workbookId string = workbook.outputs.workbookId
