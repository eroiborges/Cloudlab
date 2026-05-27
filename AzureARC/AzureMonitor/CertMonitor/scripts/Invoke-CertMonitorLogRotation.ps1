#Requires -Version 5.1
<#
.SYNOPSIS
    Rotates and cleans up CertMonitor log files to prevent unbounded disk growth.

.DESCRIPTION
    AMA (Azure Monitor Agent) ingests log files incrementally using byte-offset
    checkpoints, so data already uploaded is NOT re-ingested after rotation.

    This script performs two operations on each *.log and *.csv file in the
    monitoring folder:

    1. ROTATE  – When a file exceeds $MaxFileSizeMB, rename it to
                 <name>_<date>.log|csv and let certcollect.ps1 create a fresh
                 file. AMA picks up the new empty file automatically.

    2. PURGE   – Delete rotated archive files older than $RetainDays days.

    Run as a Scheduled Task once every 24 hours (recommended: 02:00 AM).
    Install-CertMonitor.ps1 does NOT schedule this script — add it manually
    or extend Install-CertMonitor.ps1 to include it.

.PARAMETER LogDirectory
    Directory containing CertHealth.log and CertMetricLog.csv.
    Default: C:\WindowsAzure\Certs\logs

.PARAMETER MaxFileSizeMB
    Rotate the active file when it exceeds this size in MB. Default: 50

.PARAMETER RetainDays
    Delete rotated archives older than this many days. Default: 7

.EXAMPLE
    .\Invoke-CertMonitorLogRotation.ps1

.EXAMPLE
    .\Invoke-CertMonitorLogRotation.ps1 -MaxFileSizeMB 100 -RetainDays 14

.NOTES
    Safe to run while AMA and certcollect.ps1 are running.
    AMA detects the new (empty) file and continues ingesting new lines.
    Rotated archives are no longer tracked by AMA — no duplicate ingestion.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$LogDirectory = 'C:\WindowsAzure\Certs\logs',

    [Parameter()]
    [int]$MaxFileSizeMB = 50,

    [Parameter()]
    [int]$RetainDays = 7
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EVENT_SOURCE = 'ADMonitoringScript'
$EVENT_LOG    = 'Application'
$TIMESTAMP    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$DateStamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$MaxBytes     = $MaxFileSizeMB * 1MB

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-EventEntry {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = 'Information',
        [int]$EventId = 2000
    )
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EVENT_SOURCE, $EVENT_LOG)
        }
        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE `
            -EventId $EventId -EntryType $EntryType -Message $Message
    } catch {
        Write-Warning "Event log write failed: $_"
    }
}

function Write-Status {
    param([string]$Message)
    Write-Host "$TIMESTAMP $Message"
}

# ---------------------------------------------------------------------------
# Guard: log directory must exist
# ---------------------------------------------------------------------------
if (-not (Test-Path $LogDirectory)) {
    Write-Status "Log directory does not exist — nothing to rotate: $LogDirectory"
    exit 0
}

Write-Status "=== CertMonitor Log Rotation: $LogDirectory ==="
Write-Status "Max file size : ${MaxFileSizeMB} MB | Retain archives : ${RetainDays} days"
Write-Status ''

$rotated = 0
$purged  = 0

# ---------------------------------------------------------------------------
# Active files to consider for rotation: .log and .csv
# (excludes already-rotated archives that contain a date stamp)
# ---------------------------------------------------------------------------
$activeFiles = Get-ChildItem -Path $LogDirectory -File |
               Where-Object { $_.Extension -in '.log', '.csv' -and $_.Name -notmatch '_\d{8}_\d{6}' }

foreach ($file in $activeFiles) {
    if ($file.Length -gt $MaxBytes) {
        $ext      = $file.Extension
        $baseName = $file.BaseName
        $archive  = Join-Path $LogDirectory "${baseName}_${DateStamp}${ext}"

        try {
            Rename-Item -Path $file.FullName -NewName $archive -Force
            Write-Status "ROTATED  : $($file.Name) → $(Split-Path $archive -Leaf)  ($([math]::Round($file.Length / 1MB, 1)) MB)"
            Write-EventEntry -Message "CertMonitor: Rotated $($file.Name) ($([math]::Round($file.Length/1MB,1)) MB) → $(Split-Path $archive -Leaf)" -EventId 2010
            $rotated++
        } catch {
            Write-Warning "ROTATE FAILED: $($file.Name) — $_"
            Write-EventEntry -Message "CertMonitor: Failed to rotate $($file.Name): $_" `
                -EntryType 'Warning' -EventId 2011
        }
    } else {
        Write-Status "OK       : $($file.Name)  ($([math]::Round($file.Length / 1MB, 2)) MB — below ${MaxFileSizeMB} MB threshold)"
    }
}

# ---------------------------------------------------------------------------
# Purge old archives
# ---------------------------------------------------------------------------
$cutoff  = (Get-Date).AddDays(-$RetainDays)
$archives = Get-ChildItem -Path $LogDirectory -File |
            Where-Object { $_.Name -match '_\d{8}_\d{6}\.(log|csv)$' }

foreach ($archive in $archives) {
    if ($archive.LastWriteTime -lt $cutoff) {
        try {
            Remove-Item -Path $archive.FullName -Force
            Write-Status "PURGED   : $($archive.Name)  (last modified: $($archive.LastWriteTime.ToString('yyyy-MM-dd')))"
            $purged++
        } catch {
            Write-Warning "PURGE FAILED: $($archive.Name) — $_"
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Status ''
Write-Status "=== Done: $rotated file(s) rotated, $purged archive(s) purged ==="
Write-EventEntry -Message "CertMonitor log rotation: $rotated rotated, $purged purged. Directory: $LogDirectory" -EventId 2012
