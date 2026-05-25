#Requires -Version 5.1
<#
.SYNOPSIS
    Creates or updates the CertHealth_CL custom table in a Log Analytics workspace.

.DESCRIPTION
    Uses the Log Analytics Tables REST API (2022-10-01) to create the CertHealth_CL
    custom table with the schema expected by certcollect.ps1.
    If the table already exists, the schema is updated (PUT is idempotent).

    Requires an active Azure login (Connect-AzAccount) with permissions to write
    tables in the target workspace (Contributor or Log Analytics Contributor).

.PARAMETER SubscriptionId
    Azure subscription that contains the Log Analytics workspace.

.PARAMETER ResourceGroupName
    Resource group that contains the Log Analytics workspace.

.PARAMETER WorkspaceName
    Name of the Log Analytics workspace.

.PARAMETER TableName
    Name of the custom table. Default: CertHealth_CL

.EXAMPLE
    .\New-CertHealthTable.ps1 `
        -SubscriptionId  'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -ResourceGroupName 'rg-monitoring' `
        -WorkspaceName   'law-prod'

.NOTES
    Run once per workspace. Re-running is safe (idempotent PUT).
    Requires Az.Accounts module (Connect-AzAccount).
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$WorkspaceName,

    [Parameter()]
    [string]$TableName = 'CertHealth_CL'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Table schema
# ---------------------------------------------------------------------------
# Columns match the key=value fields emitted by certcollect.ps1:
#   ScriptName  – always 'certcollect'
#   Source      – CertStore:My | IIS:SiteName | RDP | WinRM | SQLServer:Inst
#   MetricName  – CertDaysToExpiry | CertChainValid | CACertDaysToExpiry
#   Store       – My | WebHosting | CA
#   Thumbprint  – certificate SHA-1 thumbprint
#   Status      – Healthy | Warning | Critical | Expired | Valid | ...
#   Severity    – OK | Warning | Critical | Error
#   Value       – numeric metric value
#   Subject     – certificate subject (DN, commas replaced with semicolons)
#   Message     – human-readable description
#   Event       – Start | End | StoreScanned | Error | ... (operational events)

$tableSchema = @{
    properties = @{
        schema = @{
            name    = $TableName
            columns = @(
                @{ name = 'TimeGenerated'; type = 'datetime' }
                @{ name = 'ScriptName';   type = 'string'   }
                @{ name = 'Source';       type = 'string'   }
                @{ name = 'MetricName';   type = 'string'   }
                @{ name = 'Store';        type = 'string'   }
                @{ name = 'Thumbprint';   type = 'string'   }
                @{ name = 'Status';       type = 'string'   }
                @{ name = 'Severity';     type = 'string'   }
                @{ name = 'Value';        type = 'real'     }
                @{ name = 'Subject';      type = 'string'   }
                @{ name = 'Message';      type = 'string'   }
                @{ name = 'Event';        type = 'string'   }
            )
        }
        # No explicit retention — table inherits workspace default (matches SQLMonitoring_CL pattern)
    }
} | ConvertTo-Json -Depth 6

# ---------------------------------------------------------------------------
# Build REST URI
# ---------------------------------------------------------------------------
$apiVersion = '2022-10-01'
$uri = ('https://management.azure.com/subscriptions/{0}/resourceGroups/{1}' +
        '/providers/Microsoft.OperationalInsights/workspaces/{2}/tables/{3}?api-version={4}') -f
        $SubscriptionId, $ResourceGroupName, $WorkspaceName, $TableName, $apiVersion

Write-Host "Target workspace : $WorkspaceName"
Write-Host "Table            : $TableName"
Write-Host "Retention        : workspace default"
Write-Host "URI              : $uri"
Write-Host ''

# ---------------------------------------------------------------------------
# Call REST API
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess("$WorkspaceName/$TableName", 'Create or update custom table')) {
    try {
        $response = Invoke-AzRestMethod -Uri $uri -Method PUT -Payload $tableSchema
        if ($response.StatusCode -in 200, 201, 202) {
            Write-Host "SUCCESS: Table '$TableName' created/updated (HTTP $($response.StatusCode))." -ForegroundColor Green
        } else {
            Write-Error "Unexpected HTTP $($response.StatusCode): $($response.Content)"
        }
    } catch {
        Write-Error "Failed to create table: $_"
    }
}
