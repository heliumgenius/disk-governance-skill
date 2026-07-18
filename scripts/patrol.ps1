#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Phase 2: Scan for anomalous files during task execution.
.DESCRIPTION
    Compares current working directory state against the Phase 1 snapshot.
    Detects new files outside expected scope, large unexpected files,
    and agent runtime cache growth.
.PARAMETER SessionId
    Session ID returned by snapshot.ps1.
.PARAMETER WorkingDir
    The directory the agent is working in.
.PARAMETER DetectOrphans
    Switch to also scan for orphan processes.
.PARAMETER GovernanceDir
    Override governance data directory.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDir,
    [switch]$DetectOrphans,
    [string]$GovernanceDir = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "utils.ps1")

if (-not $GovernanceDir) { $GovernanceDir = Join-Path $WorkingDir ".disk-governance" }
$snapshotDir = Join-Path $GovernanceDir "snapshots"
$logDir = Join-Path $GovernanceDir "logs"
$snapshotPath = Join-Path $snapshotDir "$SessionId.json"

if (-not (Test-Path $snapshotPath)) {
    Write-Error "Snapshot not found: $snapshotPath. Run snapshot.ps1 first."
    exit 1
}

$snapshot = Get-Content $snapshotPath -Raw | ConvertFrom-Json

# Load rules
$rulesPath = Join-Path $scriptDir "..\rules\default.json"
$rules = @{}
if (Test-Path $rulesPath) {
    $rules = Get-Content $rulesPath -Raw | ConvertFrom-Json
}

$anomalies = @()

# 1. Scan working directory for new files
if (Test-Path $WorkingDir) {
    $currentFiles = Get-FileTree -Path $WorkingDir
    $snapshotFiles = $snapshot.FileTree | ForEach-Object { $_.Path }

    $currentFiles | ForEach-Object {
        $relPath = $_.Path
        $isNew = $relPath -notin $snapshotFiles

        if (-not $isNew) { return }

        # Skip governance internals
        if ($relPath -like "*\.disk-governance\*") { return }

        # Check protected patterns
        $isProtected = $false
        foreach ($pattern in $rules.protected_patterns) {
            $regex = [WildcardPattern]::Escape($pattern).Replace('\*\*', '.*').Replace('\*', '[^\\]*')
            if ($relPath -match $regex) { $isProtected = $true; break }
        }
        if ($isProtected) { return }

        # Classify anomaly
        $isAuto = $false
        foreach ($pattern in $rules.auto_delete_patterns) {
            $regex = [WildcardPattern]::Escape($pattern).Replace('\*\*', '.*').Replace('\*', '[^\\]*')
            if ($relPath -match $regex) { $isAuto = $true; break }
        }

        $anomalies += [PSCustomObject]@{
            Path = $_.Path
            Size = $_.Size
            SizeMB = [math]::Round($_.Size / 1MB, 2)
            LastWriteTime = $_.LastWriteTime
            Classification = if ($isAuto) { "auto" } else { "confirm" }
            Source = "new_file"
            Extension = $_.Extension
        }
    }
}

# 2. Check agent runtime paths
$agentPaths = $rules.agent_runtime_paths
if ($agentPaths) {
    foreach ($toolName in $agentPaths.PSObject.Properties.Name) {
        $paths = $agentPaths.$toolName
        foreach ($p in $paths) {
            $resolvedPath = [System.Environment]::ExpandEnvironmentVariables($p)
            if (Test-Path $resolvedPath) {
                $size = Get-DirectorySize -Path $resolvedPath
                if ($size -gt 50MB) {
                    $anomalies += [PSCustomObject]@{
                        Path = $resolvedPath
                        Size = $size
                        SizeMB = [math]::Round($size / 1MB, 2)
                        Classification = "confirm"
                        Source = "agent_runtime_$toolName"
                    }
                }
            }
        }
    }
}

# 3. Check system temp for new agent-created files
$tempPath = $env:TEMP
if ($tempPath -and (Test-Path $tempPath)) {
    $currentTemp = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue |
                   Select-Object Name, Length, LastWriteTime
    $snapshotTemp = $snapshot.SystemTemp.Files | ForEach-Object { $_.Name }

    $currentTemp | Where-Object { $_.Name -notin $snapshotTemp -and $_.Length -gt 1MB } |
        ForEach-Object {
            $anomalies += [PSCustomObject]@{
                Path = Join-Path $tempPath $_.Name
                Size = $_.Length
                SizeMB = [math]::Round($_.Length / 1MB, 2)
                Classification = "auto"
                Source = "system_temp"
            }
        }
}

# 4. Check Desktop/Downloads for new files
$desktop = [Environment]::GetFolderPath("Desktop")
$downloads = Join-Path $env:USERPROFILE "Downloads"

@($desktop, $downloads) | ForEach-Object {
    $loc = $_
    $label = if ($_ -eq $desktop) { "Desktop" } else { "Downloads" }
    $snapshotFiles = $snapshot.$label.Files | ForEach-Object { $_.Name }

    if (Test-Path $loc) {
        Get-ChildItem -Path $loc -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $snapshotFiles -and $_.Length -gt 1MB } |
            ForEach-Object {
                $anomalies += [PSCustomObject]@{
                    Path = $_.FullName
                    Size = $_.Length
                    SizeMB = [math]::Round($_.Length / 1MB, 2)
                    Classification = "confirm"
                    Source = $label
                }
            }
    }
}

# 5. Optional: detect orphan processes
if ($DetectOrphans) {
    $orphans = Get-Process | Where-Object {
        $_.ProcessName -match "tmpclaude|playwright|chrom" -and
        $_.StartTime -lt (Get-Date).AddMinutes(-30)
    } | Select-Object Id, ProcessName, StartTime, @{Name="CPU";Expression={[math]::Round($_.CPU, 1)}}

    $orphans | ForEach-Object {
        $anomalies += [PSCustomObject]@{
            Path = "PID:$($_.Id)"
            Size = 0
            SizeMB = 0
            Classification = "confirm"
            Source = "orphan_process"
            ProcessName = $_.ProcessName
            CPU = $_.CPU
            Started = $_.StartTime
        }
    }
}

# Generate report
$report = @{
    Timestamp = Get-Timestamp
    SessionId = $SessionId
    TotalAnomalies = $anomalies.Count
    AutoCleanCount = @($anomalies | Where-Object { $_.Classification -eq "auto" }).Count
    ConfirmCount = @($anomalies | Where-Object { $_.Classification -eq "confirm" }).Count
    Anomalies = $anomalies
    FreeSpaceGB = (Get-FreeSpace -DriveLetter ((Get-Item $WorkingDir).PSDrive.Name)).FreeGB
}

# Write report
$reportPath = Join-Path $logDir "patrol-$(Get-Date -Format 'yyyyMMddHHmmss').json"
$report | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath

Write-GovernanceLog -SessionId $SessionId -Phase "patrol" -Message "Patrol complete: $($anomalies.Count) anomalies" -LogDir $logDir

$report | ConvertTo-Json -Compress -Depth 5
