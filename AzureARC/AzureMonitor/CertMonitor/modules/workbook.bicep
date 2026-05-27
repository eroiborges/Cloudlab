// =============================================================================
// modules/workbook.bicep
// Azure Monitor Workbook – Certificate Health Dashboard
//
// Displays certificate expiry, chain validity, and source-grouped inventory
// for all Windows servers reporting via Azure Arc + AMA + certcollect.ps1.
//
// Filters:
//   • Time Range
//   • Server Name  (extracted from Arc machine _ResourceId)
//   • Source Type  (CertStore | IIS | RDP | WinRM | SQLServer)
//   • Severity     (OK | Warning | Critical | Error)
// =============================================================================

param location string
param workspaceResourceId string
param tags object = {}

var workbookContent = loadJsonContent('../workbook/cert-workbook.json')

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  // guid() is deterministic per workspace — re-deploying updates the same workbook
  name: guid('cert-health-workbook', workspaceResourceId)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Certificate Health Dashboard'
    description: 'Monitors certificate expiry and chain validity for Windows servers via Azure Arc AMA. Filters by server, source type, and severity.'
    category: 'workbook'
    serializedData: replace(string(workbookContent), '__WORKSPACE_RESOURCE_ID__', workspaceResourceId)
    sourceId: 'Azure Monitor'
    version: '1.0'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the deployed workbook.')
output workbookId string = workbook.id
