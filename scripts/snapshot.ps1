#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Phase 1: Record disk state before task execution.
.DESCRIPTION
    Takes a snapshot of working directory, system temp, desktop, and downloads.
    Checks free space thresholds. Returns session ID and snapshot path.
.PARAMETER WorkingDir
    The directory the agent will work in.
.PARAMETER ConfigDir
    Override config directory (default: ~/.config/disk-governance).
.PARAMETER GovernanceDir
    Override governance data directory (default: WorkingDir/.disk-governance).
.EXAMPLE
    .\snapshot.ps1 -WorkingDir "C:\Users\heliner\project"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDir,
    [string]$ConfigDir = "$env:USERPROFILE\.config\disk-governance",
    [string]$GovernanceDir = ""
)

# Import helpers
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "utils.ps1")

if (-not $GovernanceDir) { $GovernanceDir = Join-Path $WorkingDir ".disk-governance" }

# Ensure directories exist
$snapshotDir = Join-Path $GovernanceDir "snapshots"
$logDir = Join-Path $GovernanceDir "logs"
New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# Generate session ID
$sessionId = New-SessionId
Write-GovernanceLog -SessionId $sessionId -Phase "snapshot" -Message "Session started" -LogDir $logDir

# Load config
$configPath = Join-Path $ConfigDir "config.yaml"
if (-not (Test-Path $configPath)) { $configPath = $null }

# Acquire lock
$lockPath = Join-Path $GovernanceDir "governance.lock"
try { New-LockFile -Path $lockPath } catch { throw; return }

# Snapshot data
$snapshot = @{
    SessionId = $sessionId
    Timestamp = Get-Timestamp
    WorkingDir = $WorkingDir
    FreeSpace = @{}
    SystemTemp = @{}
    FileTree = @()
    Config = @{}
}

# Check drive free space
$drive = (Get-Item $WorkingDir).PSDrive.Name
$space = Get-FreeSpace -DriveLetter $drive
$snapshot.FreeSpace = $space

# Check thresholds
$minFree = 5  # default GB
if ($configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Yaml 2>$null
    if ($config -and $config.min_free_space_gb) { $minFree = $config.min_free_space_gb }
}

if ($space.FreeGB -lt $minFree) {
    $warning = "Low disk space: $($space.FreeGB) GB free on $($drive):\ (threshold: ${minFree}GB)"
    Write-Warning $warning
    Write-GovernanceLog -SessionId $sessionId -Phase "snapshot" -Message $warning -LogDir $logDir
}

# Snapshot working directory file tree
if (Test-Path $WorkingDir) {
    $snapshot.FileTree = Get-FileTree -Path $WorkingDir
}

# Snapshot system temp
$tempPath = $env:TEMP
if ($tempPath -and (Test-Path $tempPath)) {
    $snapshot.SystemTemp = @{
        Path = $tempPath
        Size = Get-DirectorySize -Path $tempPath
        Files = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue |
                Select-Object Name, Length, LastWriteTime
    }
}

# Snapshot Desktop and Downloads
$desktop = [Environment]::GetFolderPath("Desktop")
$downloads = Join-Path $env:USERPROFILE "Downloads"
$snapshot.Desktop = @{
    Path = $desktop
    Files = Get-ChildItem -Path $desktop -Force -ErrorAction SilentlyContinue |
            Select-Object Name, Length, LastWriteTime
}
$snapshot.Downloads = @{
    Path = $downloads
    Files = Get-ChildItem -Path $downloads -Force -ErrorAction SilentlyContinue |
            Select-Object Name, Length, LastWriteTime
}

# Save snapshot
$snapshotPath = Join-Path $snapshotDir "$sessionId.json"
$snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $snapshotPath

# Remove lock
Remove-LockFile -Path $lockPath

Write-GovernanceLog -SessionId $sessionId -Phase "snapshot" -Message "Snapshot saved to $snapshotPath" -LogDir $logDir

# Return session ID as JSON for agent consumption
$output = @{
    SessionId = $sessionId
    SnapshotPath = $snapshotPath
    FreeSpaceGB = $space.FreeGB
    TotalSpaceGB = $space.TotalGB
    Warnings = @()
}

if ($space.FreeGB -lt $minFree) {
    $output.Warnings += "Low disk space: $($space.FreeGB) GB free (threshold: ${minFree}GB)"
}

$output | ConvertTo-Json -Compress
