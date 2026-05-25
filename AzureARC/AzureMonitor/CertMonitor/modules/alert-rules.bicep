// =============================================================================
// modules/alert-rules.bicep
// Azure Monitor Alert Rules – Certificate Health Monitoring
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
// 1. Certificate Expired or Expiring within 30 days  (Critical / Error)
//    Covers: CertStore, IIS, RDP, WinRM, SQLServer sources
//    Severity: 1 (High) — immediate action required
// ---------------------------------------------------------------------------
resource alertCertCritical 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-cert-expiry-critical'
  location: location
  tags: tags
  properties: {
    description: 'Certificate has expired or will expire within 30 days. Covers all monitored sources (CertStore, IIS, RDP, WinRM, SQLServer).'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where MetricName == "CertDaysToExpiry"
            | where Severity in ("Critical", "Error")
            | project TimeGenerated, Source, Store, Thumbprint, Subject, Value, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Source',     operator: 'Include', values: [ '*' ] }
            { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
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
// 2. Certificate Expiring within 60 days  (Warning)
//    Severity: 2 (Medium) — plan renewal
// ---------------------------------------------------------------------------
resource alertCertWarning 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-cert-expiry-warning'
  location: location
  tags: tags
  properties: {
    description: 'Certificate will expire within 60 days. Plan renewal. Covers all monitored sources.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT2H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where MetricName == "CertDaysToExpiry"
            | where Severity == "Warning"
            | project TimeGenerated, Source, Store, Thumbprint, Subject, Value, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Source',     operator: 'Include', values: [ '*' ] }
            { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
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
// 3. Certificate Chain Broken  (Error)
//    Covers: CertStore, IIS, RDP, WinRM, SQLServer sources
//    Severity: 1 (High) — broken trust chain causes immediate service failure
// ---------------------------------------------------------------------------
resource alertCertChainBroken 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-cert-chain-broken'
  location: location
  tags: tags
  properties: {
    description: 'Certificate chain validation failed — trust chain is broken. Service connections will be rejected.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where MetricName == "CertChainValid"
            | where Value == 0
            | project TimeGenerated, Source, Store, Thumbprint, Subject, Status, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Source',     operator: 'Include', values: [ '*' ] }
            { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
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
// 4. Intermediate CA Certificate Expiring within 7 days  (Warning / Error)
//    Severity: 1 (High) — expired CA cert breaks ALL chains signed by it
// ---------------------------------------------------------------------------
resource alertCACertExpiry 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ca-cert-expiry'
  location: location
  tags: tags
  properties: {
    description: 'Intermediate CA certificate expiring within 7 days or already expired. All certificates signed by this CA will fail chain validation.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT2H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where MetricName == "CACertDaysToExpiry"
            | where Severity in ("Warning", "Error")
            | project TimeGenerated, Source, Thumbprint, Subject, Value, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
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
// 5. IIS Certificate Expired or Expiring within 30 days  (Critical / Error)
//    Separate from rule #1: includes IIS site name dimension for clearer triage
// ---------------------------------------------------------------------------
resource alertIISCertCritical 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-iis-cert-expiry-critical'
  location: location
  tags: tags
  properties: {
    description: 'IIS HTTPS binding certificate has expired or expires within 30 days. Website will show SSL errors to clients.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where MetricName == "CertDaysToExpiry"
            | where Source startswith "IIS:"
            | where Severity in ("Critical", "Error")
            | extend SiteName = tostring(split(Source, ":")[1])
            | project TimeGenerated, Source, SiteName, Thumbprint, Subject, Value, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Source',     operator: 'Include', values: [ '*' ] }
            { name: 'Thumbprint', operator: 'Include', values: [ '*' ] }
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
// 6. Script collection errors  (Error)
//    Fires when certcollect.ps1 logs an Event=Error or source-level failures
//    Severity: 3 (Low) — operational, does not affect certificate state
// ---------------------------------------------------------------------------
resource alertCollectionError 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-cert-collection-error'
  location: location
  tags: tags
  properties: {
    description: 'certcollect.ps1 encountered an error while collecting certificate data. Check the agent and script configuration.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT30M'
    windowSize: 'PT1H'
    scopes: [ workspaceResourceId ]
    criteria: {
      allOf: [
        {
          query: '''
            CertHealth_CL
            | where Event in ("Error", "StoreError", "IMDSError", "MetricPushError")
            | project TimeGenerated, Source, Event, Message
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
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
