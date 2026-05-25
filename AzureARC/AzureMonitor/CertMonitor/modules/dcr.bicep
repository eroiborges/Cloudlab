// =============================================================================
// modules/dcr.bicep
// Data Collection Rule – Certificate Health Monitoring
//
// Instructs Azure Monitor Agent to:
//   • Tail CertHealth.log (written by certcollect.ps1)
//   • Apply a KQL transform to parse key=value log lines into typed columns
//   • Route rows to CertHealth_CL in the target Log Analytics workspace
// =============================================================================

param location string
param workspaceResourceId string
param tags object = {}

@description('Full path to CertHealth.log on monitored VMs.')
param logFilePath string = 'C:\\WindowsAzure\\Certs\\logs\\CertHealth.log'

// ---------------------------------------------------------------------------
// Data Collection Rule
// ---------------------------------------------------------------------------

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'DCR-CertHealth-Monitoring'
  location: location
  tags: tags
  properties: {
    description: 'Collects CertHealth.log from Windows VMs running certcollect.ps1 and routes to CertHealth_CL in Log Analytics.'

    // -----------------------------------------------------------------------
    // Data Sources
    // -----------------------------------------------------------------------
    dataSources: {
      logFiles: [
        {
          name: 'CertHealthLog'
          streams: [ 'Custom-CertHealth_CL' ]
          filePatterns: [ logFilePath ]
          format: 'text'
          settings: {
            text: {
              // Matches the timestamp prefix written by Write-LogEntry in certcollect.ps1
              // Valid API values use uppercase: YYYY-MM-DD HH:MM:SS
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
          workspaceResourceId: workspaceResourceId
          name: 'certHealthWorkspace'
        }
      ]
    }

    // -----------------------------------------------------------------------
    // Data Flows + KQL Transform
    //
    // Log line format (metric/alert events):
    //   yyyy-MM-dd HH:mm:ss ScriptName=X,Source=X,MetricName=X,Store=X,
    //                        Thumbprint=X,Status=X,Severity=X,Value=X,
    //                        Subject=X,Message=X
    //
    // Log line format (operational events):
    //   yyyy-MM-dd HH:mm:ss ScriptName=X,Event=X[,key=value,...]
    //
    // Notes:
    //   - parse-kv is NOT supported in DCR ingestion-time transforms.
    //   - Each field is extracted with a dedicated extract() call.
    //   - Fields with fixed single-word values use [^,]* to stop at the next comma.
    //   - Subject and Message are last in the line and may contain '=' (X.500 DNs);
    //     Subject is anchored by ',Message=' and Message runs to end-of-line.
    // -----------------------------------------------------------------------
    dataFlows: [
      {
        streams: [ 'Custom-CertHealth_CL' ]
        destinations: [ 'certHealthWorkspace' ]
        transformKql: '''
          source
          | extend TimeGenerated = todatetime(extract(@'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1, RawData))
          | extend _payload    = extract(@'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (.*)', 1, RawData)
          | extend ScriptName  = extract(@'(?:^|,)ScriptName=([^,]*)',  1, _payload)
          | extend Source      = extract(@'(?:^|,)Source=([^,]*)',       1, _payload)
          | extend MetricName  = extract(@'(?:^|,)MetricName=([^,]*)',   1, _payload)
          | extend Store       = extract(@'(?:^|,)Store=([^,]*)',        1, _payload)
          | extend Thumbprint  = extract(@'(?:^|,)Thumbprint=([^,]*)',   1, _payload)
          | extend Status      = extract(@'(?:^|,)Status=([^,]*)',       1, _payload)
          | extend Severity    = extract(@'(?:^|,)Severity=([^,]*)',     1, _payload)
          | extend Value       = toreal(extract(@'(?:^|,)Value=([^,]*)', 1, _payload))
          | extend Event       = extract(@'(?:^|,)Event=([^,]*)',        1, _payload)
          | extend Subject     = extract(@'(?:^|,)Subject=(.*?)(?:,Message=|$)', 1, _payload)
          | extend Message     = extract(@'(?:^|,)Message=(.*?)$',       1, _payload)
          | project-away _payload
        '''
        outputStream: 'Custom-CertHealth_CL'
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the DCR — use this to create DCR associations on VMs.')
output dcrResourceId string = dcr.id

@description('Name of the DCR.')
output dcrName string = dcr.name
