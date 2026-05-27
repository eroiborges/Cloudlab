#Requires -Version 5.1
<#
.SYNOPSIS
    Rotates and cleans up SQL Monitor log files to prevent unbounded disk growth.

.DESCRIPTION
    AMA (Azure Monitor Agent) ingests log files incrementally using byte-offset
    checkpoints, so data already uploaded is NOT re-ingested after rotation.

    This script performs two operations on each *.log file in the log directory:

    1. ROTATE  – When a log file exceeds $MaxFileSizeMB, rename it to
                 <name>_<date>.log and let the monitoring scripts create a
                 fresh file. AMA will pick up the new file automatically.

    2. PURGE   – Delete rotated archive files older than $RetainDays days.

    Run as a Scheduled Task once every 24 hours (recommended: 02:00 AM).

.PARAMETER LogDirectory
    Directory containing the monitoring log files. Default: C:\SQLMonitoring\Logs

.PARAMETER MaxFileSizeMB
    Rotate the active log when it exceeds this size in MB. Default: 50

.PARAMETER RetainDays
    Delete rotated archives older than this many days. Default: 7

.EXAMPLE
    .\Invoke-SQLMonitorLogRotation.ps1

.EXAMPLE
    .\Invoke-SQLMonitorLogRotation.ps1 -MaxFileSizeMB 100 -RetainDays 14

.NOTES
    Safe to run while AMA and monitoring scripts are running.
    AMA detects the new (empty) log file and continues ingesting new lines.
    The rotated archive is no longer tracked by AMA so no duplicate ingestion occurs.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$LogDirectory = 'C:\SQLMonitoring\Logs',

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
    param([string]$Message, [System.Diagnostics.EventLogEntryType]$EntryType = 'Information', [int]$EventId = 1000)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EVENT_SOURCE)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EVENT_SOURCE, $EVENT_LOG)
        }
        Write-EventLog -LogName $EVENT_LOG -Source $EVENT_SOURCE -EventId $EventId -EntryType $EntryType -Message $Message
    } catch {
        Write-Warning "Event log write failed: $_"
    }
}

function Write-Status {
    param([string]$Message)
    Write-Host "$TIMESTAMP $Message"
    Write-EventEntry -Message $Message
}

# ---------------------------------------------------------------------------
# Guard – directory must exist
# ---------------------------------------------------------------------------

if (-not (Test-Path $LogDirectory)) {
    Write-Status "LogRotation: directory '$LogDirectory' not found – nothing to do."
    exit 0
}

$rotated = 0
$purged  = 0

# ---------------------------------------------------------------------------
# 1. ROTATE – active logs that exceed MaxFileSizeMB
# ---------------------------------------------------------------------------

$activeFiles = Get-ChildItem -Path $LogDirectory -Filter '*.log' |
    Where-Object { $_.Name -notmatch '_\d{8}_\d{6}\.log$' }   # exclude already-rotated archives

foreach ($file in $activeFiles) {
    if ($file.Length -gt $MaxBytes) {
        $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + "_$DateStamp.log"
        $archivePath = Join-Path $LogDirectory $archiveName
        try {
            Move-Item -Path $file.FullName -Destination $archivePath -Force
            $rotated++
            Write-Status "LogRotation: rotated '$($file.Name)' -> '$archiveName' ($([math]::Round($file.Length/1MB,1)) MB)"
        } catch {
            Write-Warning "LogRotation: failed to rotate '$($file.Name)': $_"
        }
    }
}

# ---------------------------------------------------------------------------
# 2. PURGE – rotated archives older than RetainDays
# ---------------------------------------------------------------------------

$cutoff      = (Get-Date).AddDays(-$RetainDays)
$archiveFiles = Get-ChildItem -Path $LogDirectory -Filter '*.log' |
    Where-Object { $_.Name -match '_\d{8}_\d{6}\.log$' -and $_.LastWriteTime -lt $cutoff }

foreach ($file in $archiveFiles) {
    try {
        Remove-Item -Path $file.FullName -Force
        $purged++
        Write-Status "LogRotation: purged '$($file.Name)' (last write: $($file.LastWriteTime.ToString('yyyy-MM-dd')))"
    } catch {
        Write-Warning "LogRotation: failed to purge '$($file.Name)': $_"
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$summary = "LogRotation completed: $rotated file(s) rotated, $purged archive(s) purged. " +
           "Directory: '$LogDirectory', MaxSize: ${MaxFileSizeMB}MB, Retain: ${RetainDays}d."
Write-Status $summary
