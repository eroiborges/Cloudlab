#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors certificate health across all sources on a Windows VM using Azure Monitor Agent.

.DESCRIPTION
    Checks certificate expiry and chain validity from multiple sources on the local machine:
      - CertStore  : Cert:\LocalMachine\My, WebHosting (and optionally others via -Stores)
      - CertStore  : Cert:\LocalMachine\CA  (intermediate CA certs)
      - IIS        : HTTPS bindings on all IIS sites (requires WebAdministration module)
      - RDP        : Remote Desktop Services TLS certificate
      - WinRM      : WinRM HTTPS listener certificate
      - SQLServer  : Per-instance SSL/TLS certificate (from registry)

    If -Source is omitted, all sources are checked.
    If -Source is specified, only those source blocks run.

    Two output files are written to -MonitoringFolder:
      CertHealth.log     – structured key=value diagnostic log (→ Log Analytics via AMA custom log DCR)
      CertMetricLog.csv  – numeric metric rows (→ AMA DCR or Azure Monitor Metrics REST API)

    -UploadMode DCR     : writes CertMetricLog.csv; AMA picks it up via a custom log DCR.
    -UploadMode Metrics : pushes metrics directly to Azure Monitor Metrics REST API
                          using the VM Managed Identity (no CSV written).

    Errors are also emitted to the Windows Application Event Log (Source: ADMonitoringScript).

.PARAMETER MonitoringFolder
    Directory where CertHealth.log and CertMetricLog.csv are written.
    Default: C:\WindowsAzure\Certs\logs

.PARAMETER Stores
    Certificate store names under Cert:\LocalMachine\ to include in the CertStore source.
    Default: My, WebHosting

.PARAMETER Source
    Restricts execution to one or more source types.
    Valid values: CertStore, IIS, RDP, WinRM, SQLServer
    Default: empty (all sources run).

.PARAMETER UploadMode
    DCR     – write CertMetricLog.csv for AMA pickup (default).
    Metrics – push directly to Azure Monitor Metrics REST API via Managed Identity.

.EXAMPLE
    .\certcollect.ps1

.EXAMPLE
    .\certcollect.ps1 -Source IIS,RDP

.EXAMPLE
    .\certcollect.ps1 -UploadMode Metrics

.EXAMPLE
    .\certcollect.ps1 -Source CertStore -MonitoringFolder 'D:\CertLogs' -Stores @('My','WebHosting','TrustedPublisher')

.NOTES
    Run as a Scheduled Task on every monitored Windows VM every 15 minutes.
    Requires local Administrator privileges to read all certificate stores and write to the Event Log.
    For -UploadMode Metrics: System-assigned Managed Identity must be enabled on the VM,
    with the 'Monitoring Metrics Publisher' role on the VM resource.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$MonitoringFolder = 'C:\WindowsAzure\Certs\logs',

    [Parameter()]
    [string[]]$Stores = @('My', 'WebHosting'),

    [Parameter()]
    [ValidateSet('CertStore', 'IIS', 'RDP', 'WinRM', 'SQLServer')]
    [string[]]$Source = @(),

    [Parameter()]
    [ValidateSet('DCR', 'Metrics')]
    [string]$UploadMode = 'DCR'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$SCRIPT_NAME   = 'certcollect'
$EVENT_SOURCE  = 'ADMonitoringScript'
$EVENT_LOG     = 'Application'
$LOG_FILE      = Join-Path $MonitoringFolder 'CertHealth.log'
$METRIC_FILE   = Join-Path $MonitoringFolder 'CertMetricLog.csv'
$TIMESTAMP_FMT = 'yyyy-MM-dd HH:mm:ss'

# Script-level state for Metrics upload mode
$script:VMMetadata      = $null
$script:AzMonitorToken  = $null

# ---------------------------------------------------------------------------
# Helper: source filter
# ---------------------------------------------------------------------------
function Should-RunSource {
    param([string]$SourceName)
    return ($Source.Count -eq 0 -or $Source -contains $SourceName)
}

# ---------------------------------------------------------------------------
# Helper: Event Log
# ---------------------------------------------------------------------------
function Ensure-EventSource {
    if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
        [System.Diagnostics.EventLog]::CreateEventSource($EVENT_SOURCE, $EVENT_LOG)
    }
}

function Write-EventEntry {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = 'Information',
        [int]$EventId = 2000
    )
    try {
        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE `
            -EventId $EventId -EntryType $EntryType -Message $Message
    } catch {
        Write-Warning "Failed to write to Event Log: $_"
    }
}

# ---------------------------------------------------------------------------
# Helper: Diagnostic log (CertHealth.log)
# ---------------------------------------------------------------------------
function Write-LogEntry {
    param([string]$Line)
    try {
        if (-not (Test-Path $MonitoringFolder)) {
            New-Item -ItemType Directory -Path $MonitoringFolder -Force | Out-Null
        }
        $timestamp = (Get-Date).ToString($TIMESTAMP_FMT)
        "$timestamp $Line" | Out-File -FilePath $LOG_FILE -Append -Encoding utf8
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

# ---------------------------------------------------------------------------
# Helper: Azure Monitor Metrics REST API (UploadMode=Metrics)
# ---------------------------------------------------------------------------
function Get-VMMetadata {
    try {
        $meta = Invoke-RestMethod `
            -Uri     'http://169.254.169.254/metadata/instance?api-version=2021-02-01' `
            -Headers @{ Metadata = 'true' } `
            -Method  Get `
            -TimeoutSec 5
        return @{
            SubscriptionId = $meta.compute.subscriptionId
            ResourceGroup  = $meta.compute.resourceGroupName
            VMName         = $meta.compute.name
            Location       = $meta.compute.location
            ResourceId     = "/subscriptions/$($meta.compute.subscriptionId)" +
                             "/resourceGroups/$($meta.compute.resourceGroupName)" +
                             "/providers/Microsoft.Compute/virtualMachines/$($meta.compute.name)"
        }
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Event=IMDSError," +
                              "Message=$($_.Exception.Message -replace ',',';')")
        return $null
    }
}

function Get-ManagedIdentityToken {
    $uri      = 'http://169.254.169.254/metadata/identity/oauth2/token' +
                '?api-version=2018-02-01&resource=https://monitoring.azure.com/'
    $response = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } `
                    -Method Get -TimeoutSec 10
    return $response.access_token
}

function Push-MetricToAzureMonitor {
    param(
        [string]$MetricName,
        [double]$Value,
        [hashtable]$Dimensions
    )
    if ($null -eq $script:VMMetadata) { return }
    try {
        if ([string]::IsNullOrEmpty($script:AzMonitorToken)) {
            $script:AzMonitorToken = Get-ManagedIdentityToken
        }
        $dimNames  = @($Dimensions.Keys)
        $dimValues = @($Dimensions.Values)
        $body = @{
            time = (Get-Date).ToUniversalTime().ToString('o')
            data = @{
                baseData = @{
                    metric    = $MetricName
                    namespace = 'CertMonitoring'
                    dimNames  = $dimNames
                    series    = @(@{
                        dimValues = $dimValues
                        min       = $Value
                        max       = $Value
                        sum       = $Value
                        count     = 1
                    })
                }
            }
        } | ConvertTo-Json -Depth 6 -Compress

        $uri = "https://$($script:VMMetadata.Location).monitoring.azure.com" +
               "$($script:VMMetadata.ResourceId)/metrics"
        Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' `
            -Headers @{ Authorization = "Bearer $script:AzMonitorToken" } `
            -Body $body | Out-Null
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Event=MetricPushError," +
                              "MetricName=$MetricName," +
                              "Message=$($_.Exception.Message -replace ',',';')")
    }
}

# ---------------------------------------------------------------------------
# Helper: unified result emitter
# ---------------------------------------------------------------------------
function Emit-CertResult {
    param(
        [string]$CertSource,          # CertStore:My | IIS:Default Web Site | RDP | WinRM | SQLServer:INST
        [string]$MetricName,
        [string]$Store,
        [string]$Thumbprint,
        [string]$Subject,
        [string]$Status,
        [string]$Severity,            # OK | Warning | Critical | Error
        [string]$Message,
        [double]$Value,
        [hashtable]$ExtraTags = @{}
    )

    # Diagnostic log line – fixed-cardinality fields first, Subject+Message last
    # (Subject may contain commas/equals from X.500 DN; kept at end for safe regex parse)
    $logLine = ('ScriptName={0},Source={1},MetricName={2},Store={3},Thumbprint={4},' +
                'Status={5},Severity={6},Value={7},Subject={8},Message={9}') -f
                $SCRIPT_NAME, $CertSource, $MetricName, $Store, $Thumbprint,
                $Status, $Severity, $Value,
                ($Subject  -replace ',', ';'),
                ($Message  -replace ',', ';')
    Write-LogEntry -Line $logLine

    # Event Log – only on non-OK severity to reduce noise
    if ($Severity -ne 'OK') {
        $eventType = if ($Severity -eq 'Error')                  { 'Error'   }
                     elseif ($Severity -in 'Critical', 'Warning') { 'Warning' }
                     else                                          { 'Information' }
        $eventId   = if ($Severity -eq 'Error') { 2001 } else { 2002 }
        Write-EventEntry -Message $logLine -EntryType $eventType -EventId $eventId
    }

    # Output sink: DCR file or direct Metrics push
    if ($UploadMode -eq 'DCR') {
        $tags = @{
            'vm.azm.ms/certSource'     = $CertSource
            'vm.azm.ms/certThumbprint' = $Thumbprint
            'vm.azm.ms/certSubject'    = $Subject
            'vm.azm.ms/certStore'      = $Store
            'vm.azm.ms/certStatus'     = $Status
            'vm.azm.ms/certSeverity'   = $Severity
        }
        foreach ($k in $ExtraTags.Keys) { $tags[$k] = $ExtraTags[$k] }
        $tagsJson = $tags | ConvertTo-Json -Compress
        $ts = (Get-Date).ToString('o')
        "$ts,$MetricName,$Value,$tagsJson" | Out-File -FilePath $METRIC_FILE -Append -Encoding utf8
    } else {
        Push-MetricToAzureMonitor -MetricName $MetricName -Value $Value -Dimensions @{
            Source     = $CertSource
            Store      = $Store
            Thumbprint = $Thumbprint
            Status     = $Status
            Severity   = $Severity
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: shared expiry + chain checks (called by every source block)
# ---------------------------------------------------------------------------
function Invoke-CertChecks {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [string]$CertSource,
        [string]$Store,
        [hashtable]$ExtraTags = @{}
    )
    $thumbprint   = $Cert.Thumbprint
    $subject      = $Cert.Subject
    $friendlyName = if ($Cert.FriendlyName) { $Cert.FriendlyName } else { $subject }

    # --- Expiry ---
    try {
        $days     = [math]::Round(($Cert.NotAfter - (Get-Date)).TotalDays, 1)
        $status   = if ($days -le 0)   { 'Expired'  }
                    elseif ($days -le 30) { 'Critical' }
                    elseif ($days -le 60) { 'Warning'  }
                    else                  { 'Healthy'  }
        $severity = if ($days -le 0)   { 'Error'    }
                    elseif ($days -le 30) { 'Critical' }
                    elseif ($days -le 60) { 'Warning'  }
                    else                  { 'OK'       }

        Emit-CertResult `
            -CertSource  $CertSource `
            -MetricName  'CertDaysToExpiry' `
            -Store       $Store `
            -Thumbprint  $thumbprint `
            -Subject     $subject `
            -Status      $status `
            -Severity    $severity `
            -Value       $days `
            -Message     "Certificate '$friendlyName' expires in $days day(s) on $($Cert.NotAfter.ToString('yyyy-MM-dd'))." `
            -ExtraTags   ($ExtraTags + @{
                'vm.azm.ms/certFriendlyName' = $friendlyName
                'vm.azm.ms/certNotAfter'     = $Cert.NotAfter.ToString('o')
            })
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=$CertSource,MetricName=CertDaysToExpiry," +
                              "Severity=Error,Message=$($_.Exception.Message -replace ',',';')")
    }

    # --- Chain ---
    $chain = $null
    try {
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode    = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $chain.ChainPolicy.RevocationFlag    = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EntireChain
        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag

        $chainValid  = $chain.Build($Cert)
        $chainStatus = if ($chainValid) { 'Valid' } else {
            ($chain.ChainStatus | ForEach-Object { $_.StatusInformation.Trim() }) -join '; '
        }
        $chainSeverity = if ($chainValid) { 'OK' } else { 'Error' }

        Emit-CertResult `
            -CertSource  $CertSource `
            -MetricName  'CertChainValid' `
            -Store       $Store `
            -Thumbprint  $thumbprint `
            -Subject     $subject `
            -Status      $chainStatus `
            -Severity    $chainSeverity `
            -Value       ([int]$chainValid) `
            -Message     "Certificate '$friendlyName' chain: $chainStatus." `
            -ExtraTags   ($ExtraTags + @{ 'vm.azm.ms/certChainStatus' = $chainStatus })
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=$CertSource,MetricName=CertChainValid," +
                              "Severity=Error,Message=$($_.Exception.Message -replace ',',';')")
    } finally {
        if ($null -ne $chain) { $chain.Dispose() }
    }
}

# ===========================================================================
# Initialise
# ===========================================================================

try {
    if (-not (Test-Path $MonitoringFolder)) {
        New-Item -ItemType Directory -Path $MonitoringFolder -Force | Out-Null
    }
    Ensure-EventSource
} catch {
    Write-Warning "Initialisation warning: $_"
}

if ($UploadMode -eq 'Metrics') {
    $script:VMMetadata = Get-VMMetadata
    if ($null -eq $script:VMMetadata) {
        Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Event=FatalError,Message=Cannot reach IMDS; Metrics upload mode requires Managed Identity"
        exit 1
    }
    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Event=Start,UploadMode=$UploadMode," +
                          "VM=$($script:VMMetadata.VMName),Location=$($script:VMMetadata.Location)")
} else {
    Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Event=Start,UploadMode=$UploadMode,Sources=$($Source -join ';')"
}

# ===========================================================================
# Source Block 1: Certificate Stores  (CertStore)
# ===========================================================================

if (Should-RunSource 'CertStore') {
    foreach ($storeName in $Stores) {
        $certs = @()
        try {
            $certs = @(Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction Stop)
        } catch {
            Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=CertStore:$storeName,Event=StoreError," +
                                  "Message=$($_.Exception.Message -replace ',',';')")
            continue
        }

        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=CertStore:$storeName," +
                              "Event=StoreScanned,CertCount=$($certs.Count)")

        foreach ($cert in $certs) {
            Invoke-CertChecks -Cert $cert -CertSource "CertStore:$storeName" -Store $storeName
        }
    }

    # Intermediate CA store
    try {
        $caCerts = @(Get-ChildItem -Path 'Cert:\LocalMachine\CA' -ErrorAction Stop)
        Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=CertStore:CA,Event=StoreScanned,CertCount=$($caCerts.Count)"

        foreach ($ca in $caCerts) {
            if (-not $ca.NotAfter) { continue }

            $days     = [math]::Round(($ca.NotAfter - (Get-Date)).TotalDays, 1)
            $status   = if ($days -le 0) { 'Expired' } elseif ($days -le 7) { 'Warning' } else { 'Healthy' }
            $severity = if ($days -le 0) { 'Error'   } elseif ($days -le 7) { 'Warning' } else { 'OK'      }

            Emit-CertResult `
                -CertSource  'CertStore:CA' `
                -MetricName  'CACertDaysToExpiry' `
                -Store       'CA' `
                -Thumbprint  $ca.Thumbprint `
                -Subject     $ca.Subject `
                -Status      $status `
                -Severity    $severity `
                -Value       $days `
                -Message     "CA certificate expires in $days day(s) on $($ca.NotAfter.ToString('yyyy-MM-dd'))." `
                -ExtraTags   @{ 'vm.azm.ms/certIssuer' = $ca.Issuer }
        }
    } catch {
        $errMsg = $_.Exception.Message -replace ',', ';'
        Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=CertStore:CA,Event=Error,Message=$errMsg"
        Write-EventEntry -Message "certcollect CA store error: $errMsg" -EntryType 'Error' -EventId 2001
    }
}

# ===========================================================================
# Source Block 2: IIS HTTPS Bindings  (IIS)
# ===========================================================================

if (Should-RunSource 'IIS') {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        Write-LogEntry -Line 'ScriptName=certcollect,Source=IIS,Event=Skipped,Message=WebAdministration module not found - IIS not installed'
    } else {
        try {
            Import-Module WebAdministration -ErrorAction Stop
            $sslBindings = @(Get-ChildItem 'IIS:\SslBindings' -ErrorAction Stop)
            Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=IIS,Event=Scanned,BindingCount=$($sslBindings.Count)"

            foreach ($binding in $sslBindings) {
                $thumbprint = $binding.Thumbprint
                if ([string]::IsNullOrEmpty($thumbprint)) { continue }

                $siteName = if ($binding.Sites) { $binding.Sites.Value } else { 'Unknown' }
                $port     = $binding.Port
                $ipAddr   = if ($binding.IPAddress) { $binding.IPAddress } else { '*' }
                $src      = "IIS:$siteName"

                $cert = Get-ChildItem "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
                if (-not $cert) {
                    Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=$src,Event=CertNotFound," +
                                         "Thumbprint=$thumbprint,Site=$siteName")
                    continue
                }

                Invoke-CertChecks -Cert $cert -CertSource $src -Store 'My' -ExtraTags @{
                    'vm.azm.ms/iisSiteName' = $siteName
                    'vm.azm.ms/iisPort'     = "$port"
                    'vm.azm.ms/iisIP'       = "$ipAddr"
                }
            }
        } catch {
            Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=IIS,Event=Error," +
                                  "Message=$($_.Exception.Message -replace ',',';')")
        }
    }
}

# ===========================================================================
# Source Block 3: Remote Desktop Services  (RDP)
# ===========================================================================

if (Should-RunSource 'RDP') {
    try {
        $regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        $rdpProp  = Get-ItemProperty -Path $regPath -Name SSLCertificateSHA1Hash -ErrorAction Stop
        $hashBytes = $rdpProp.SSLCertificateSHA1Hash

        if ($hashBytes -and $hashBytes.Count -gt 0) {
            $thumbprint = [BitConverter]::ToString($hashBytes).Replace('-', '')
            Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=RDP,Event=Scanned,Thumbprint=$thumbprint"

            $cert = Get-ChildItem "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
            if ($cert) {
                Invoke-CertChecks -Cert $cert -CertSource 'RDP' -Store 'My'
            } else {
                Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=RDP,Event=CertNotFound,Thumbprint=$thumbprint"
            }
        } else {
            Write-LogEntry -Line 'ScriptName=certcollect,Source=RDP,Event=Skipped,Message=RDP is using an auto-generated self-signed certificate'
        }
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=RDP,Event=Error," +
                              "Message=$($_.Exception.Message -replace ',',';')")
    }
}

# ===========================================================================
# Source Block 4: WinRM HTTPS Listener  (WinRM)
# ===========================================================================

if (Should-RunSource 'WinRM') {
    try {
        $listeners = @(
            Get-ChildItem WSMan:\localhost\Listener -ErrorAction Stop |
            Where-Object { ($_ | Get-Item).Keys -contains 'Transport=HTTPS' }
        )
        Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=WinRM,Event=Scanned,HTTPSListenerCount=$($listeners.Count)"

        foreach ($listener in $listeners) {
            $thumbprint = (Get-Item "WSMan:\localhost\Listener\$($listener.PSChildName)\CertificateThumbprint" `
                              -ErrorAction SilentlyContinue).Value
            if ([string]::IsNullOrEmpty($thumbprint)) { continue }

            $cert = Get-ChildItem "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
            if ($cert) {
                Invoke-CertChecks -Cert $cert -CertSource 'WinRM' -Store 'My' -ExtraTags @{
                    'vm.azm.ms/winrmListener' = $listener.PSChildName
                }
            } else {
                Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=WinRM,Event=CertNotFound,Thumbprint=$thumbprint"
            }
        }
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=WinRM,Event=Error," +
                              "Message=$($_.Exception.Message -replace ',',';')")
    }
}

# ===========================================================================
# Source Block 5: SQL Server SSL Certificates  (SQLServer)
# ===========================================================================

if (Should-RunSource 'SQLServer') {
    try {
        $sqlRoot  = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
        $instances = @(
            Get-ChildItem $sqlRoot -ErrorAction Stop |
            Where-Object { $_.PSChildName -match '^MSSQL\d' }
        )
        Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Source=SQLServer,Event=Scanned,InstanceCount=$($instances.Count)"

        foreach ($inst in $instances) {
            $instName   = $inst.PSChildName
            $certRegPath = "$sqlRoot\$instName\MSSQLServer\SuperSocketNetLib"
            $thumbprint  = (Get-ItemProperty -Path $certRegPath -Name Certificate `
                                -ErrorAction SilentlyContinue).Certificate

            if ([string]::IsNullOrEmpty($thumbprint)) {
                Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=SQLServer:$instName," +
                                      "Event=Skipped,Message=No custom SSL certificate configured")
                continue
            }

            $cert = Get-ChildItem "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
            if ($cert) {
                Invoke-CertChecks -Cert $cert -CertSource "SQLServer:$instName" -Store 'My' -ExtraTags @{
                    'vm.azm.ms/sqlInstance' = $instName
                }
            } else {
                Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=SQLServer:$instName," +
                                      "Event=CertNotFound,Thumbprint=$thumbprint")
            }
        }
    } catch {
        Write-LogEntry -Line ("ScriptName=$SCRIPT_NAME,Source=SQLServer,Event=Error," +
                              "Message=$($_.Exception.Message -replace ',',';')")
    }
}

# ===========================================================================
# Done
# ===========================================================================

Write-LogEntry -Line "ScriptName=$SCRIPT_NAME,Event=End,UploadMode=$UploadMode"
