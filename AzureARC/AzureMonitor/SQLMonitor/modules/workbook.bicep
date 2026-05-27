// =============================================================================
// modules/workbook.bicep
// Azure Monitor Workbook – SQL Server Health Dashboard
// Replicates SCOM health views for SQL Server monitoring
// =============================================================================

param location string
param workspaceResourceId string
param tags object = {}

var workbookContent = loadJsonContent('../workbook/sql-workbook.json')

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('sql-monitoring-workbook', resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'SQL Server Monitoring Dashboard'
    description: 'Replicates SCOM SQL Server health views in Azure Monitor. Shows service health, performance, AG status, jobs, and alerts.'
    category: 'workbook'
    serializedData: replace(string(workbookContent), '__WORKSPACE_RESOURCE_ID__', workspaceResourceId)
    sourceId: 'Azure Monitor'
    version: '1.0'
  }
}

output workbookId string = workbook.id
