// =============================================================================
// main.bicep
// SQL Server Monitoring - Azure Monitor Migration from SCOM
// Migrated from: Microsoft SQL Server on Windows Management Pack
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the Log Analytics Workspace to create. Must be globally unique.')
param workspaceName string

@description('Log Analytics Workspace data retention in days (30–730). 30 = free tier; every day above 30 is billed at ~$0.10/GB/month.')
@minValue(30)
@maxValue(730)
param workspaceRetentionDays int = 30

@description('Name for the Action Group that receives alert notifications.')
param actionGroupName string = 'ag-sql-monitor'

@description('Display name for the Action Group (max 12 characters).')
@maxLength(12)
param actionGroupShortName string = 'SQLMonAlert'

@description('Email address to receive SQL monitoring alert notifications.')
param alertEmailAddress string

@description('Optional: Resource ID of an existing Data Collection Endpoint. Leave blank to skip.')
param dataCollectionEndpointId string = ''

@description('Tag: deployment environment.')
@allowed(['production', 'staging', 'development'])
param environment string = 'production'

@description('Tag: owner team or contact.')
param ownerTag string = 'IT-Operations'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var tags = {
  Environment: environment
  ManagedBy: 'AzureMonitor'
  MigratedFrom: 'SCOM-SQLServerMP'
  Solution: 'SQLMonitoring'
  Owner: ownerTag
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace (created by this template)
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
// Action Groups always use location 'global' in Azure Monitor regardless of
// the resource group region.
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
        name: 'sql-alerts-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

var actionGroupResourceId = actionGroup.id

// ---------------------------------------------------------------------------
// Pre-requisite: SQLMonitoring_CL custom log table
// Must exist before the DCR can reference the custom output stream.
// ---------------------------------------------------------------------------

resource sqlMonitoringTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: 'SQLMonitoring_CL'
  properties: {
    schema: {
      name: 'SQLMonitoring_CL'
      columns: [
        { name: 'TimeGenerated', type: 'dateTime' }
        { name: 'Computer',      type: 'string' }
        { name: 'ScriptName',    type: 'string' }
        { name: 'InstanceName',  type: 'string' }
        { name: 'DatabaseName',  type: 'string' }
        { name: 'JobName',       type: 'string' }
        { name: 'Status',        type: 'string' }
        { name: 'Severity',      type: 'string' }
        { name: 'Message',       type: 'string' }
        { name: 'MetricValue',   type: 'string' }
        { name: 'CheckResult',   type: 'string' }
        { name: 'RawData',       type: 'string' }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module dcr 'modules/dcr.bicep' = {
  name: 'deploy-sql-dcr'
  dependsOn: [ sqlMonitoringTable ]
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    dataCollectionEndpointId: dataCollectionEndpointId
    tags: tags
  }
}

module alerts 'modules/alert-rules.bicep' = {
  name: 'deploy-sql-alerts'
  dependsOn: [ sqlMonitoringTable ]
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    actionGroupResourceId: actionGroupResourceId
    tags: tags
  }
}

module workbook 'modules/workbook.bicep' = {
  name: 'deploy-sql-workbook'
  params: {
    location: location
    workspaceResourceId: workspaceResourceId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Log Analytics Workspace.')
output workspaceResourceId string = workspace.id

@description('Log Analytics Workspace ID (GUID) – use for agent configuration.')
output workspaceId string = workspace.properties.customerId

@description('Resource ID of the Data Collection Rule.')
output dcrResourceId string = dcr.outputs.dcrId

@description('Immutable ID of the DCR (needed for agent association).')
output dcrImmutableId string = dcr.outputs.dcrImmutableId

@description('Resource ID of the SQL Monitoring Workbook.')
output workbookId string = workbook.outputs.workbookId

@description('Resource ID of the Alert Action Group.')
output actionGroupResourceId string = actionGroup.id
