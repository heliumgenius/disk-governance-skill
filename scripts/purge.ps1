#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Phase 3: Compare current state vs snapshot, clean up garbage.
.DESCRIPTION
    Without -Execute: generates cleanup report only (default).
    With -Execute: performs the cleanup and generates final report.
.PARAMETER SessionId
    Session ID returned by snapshot.ps1.
.PARAMETER WorkingDir
    The directory the agent worked in.
.PARAMETER Execute
    Actually perform cleanup (default: dry-run only).
.PARAMETER GovernanceDir
    Override governance data directory.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDir,
    [switch]$Execute,
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

# Acquire lock
$lockPath = Join-Path $GovernanceDir "governance.lock"
try { New-LockFile -Path $lockPath } catch { throw; return }

Write-GovernanceLog -SessionId $SessionId -Phase "purge" -Message "Purge started (Execute=$Execute)" -LogDir $logDir

# Diff current vs snapshot
$snapshotFiles = @{}
$snapshot.FileTree | ForEach-Object { $snapshotFiles[$_.Path] = $_ }

$currentFiles = @{}
if (Test-Path $WorkingDir) {
    Get-FileTree -Path $WorkingDir | ForEach-Object { $currentFiles[$_.Path] = $_ }
}

$newFiles = @()
$currentFiles.Keys | Where-Object { $_ -notin $snapshotFiles.Keys } | ForEach-Object {
    if ($_ -like "*\.disk-governance\*") { return }
    foreach ($pattern in $rules.protected_patterns) {
        $regex = Convert-PatternToRegex -Pattern $pattern
        try { if ($_ -match $regex) { return } } catch { }
    }
    $newFiles += $currentFiles[$_]
}

# Classify each new file
$autoClean = @()
$confirmClean = @()
$keep = @()

$newFiles | ForEach-Object {
    $path = $_.Path
    $isAuto = $false
    $isConfirm = $false

    foreach ($pattern in $rules.auto_delete_patterns) {
        $regex = Convert-PatternToRegex -Pattern $pattern
        try { if ($path -match $regex) { $isAuto = $true; break } } catch { }
    }

    if (-not $isAuto) {
        foreach ($pattern in $rules.confirm_patterns) {
            $regex = Convert-PatternToRegex -Pattern $pattern
            try { if ($path -match $regex) { $isConfirm = $true; break } } catch { }
        }
    }

    $entry = [PSCustomObject]@{
        Path = $path
        Size = $_.Size
        SizeMB = [math]::Round($_.Size / 1MB, 2)
        LastWriteTime = $_.LastWriteTime
    }

    if ($isAuto) { $autoClean += $entry }
    elseif ($isConfirm) { $confirmClean += $entry }
    else { $keep += $entry }
}

# Execute cleanup if requested
$autoFreed = 0
$confirmFreed = 0
$failedDeletions = @()

if ($Execute) {
    $autoClean | ForEach-Object {
        $safePath = Resolve-PathSafe -Path $_.Path
        try {
            if ($_.Path -match "\\nul$") {
                Remove-NulFile -Path $_.Path
            } else {
                Remove-Item -Path $safePath -Force -Recurse -ErrorAction Stop
            }
            $autoFreed += $_.Size
        } catch {
            $failedDeletions += [PSCustomObject]@{ Path = $_.Path; Error = $_.Exception.Message }
        }
    }

    $confirmClean | ForEach-Object {
        $safePath = Resolve-PathSafe -Path $_.Path
        try {
            Remove-Item -Path $safePath -Force -Recurse -ErrorAction Stop
            $confirmFreed += $_.Size
        } catch {
            $failedDeletions += [PSCustomObject]@{ Path = $_.Path; Error = $_.Exception.Message }
        }
    }

    Remove-Item -Path $GovernanceDir -Force -Recurse -ErrorAction SilentlyContinue
}

# Generate report
$report = @{
    Timestamp = Get-Timestamp
    SessionId = $SessionId
    Mode = if ($Execute) { "execute" } else { "dry-run" }
    WorkingDir = $WorkingDir
    SnapshotAge = [math]::Round(((Get-Date) - [DateTime]$snapshot.Timestamp).TotalHours, 1)
    Summary = @{
        NewFilesTotal = $newFiles.Count
        AutoClean = $autoClean.Count
        Confirm = $confirmClean.Count
        Keep = $keep.Count
        AutoFreedMB = if ($Execute) { [math]::Round($autoFreed / 1MB, 2) } else { 0 }
        ConfirmFreedMB = if ($Execute) { [math]::Round($confirmFreed / 1MB, 2) } else { 0 }
        TotalFreedMB = if ($Execute) { [math]::Round(($autoFreed + $confirmFreed) / 1MB, 2) } else { 0 }
    }
    FailedDeletions = $failedDeletions
    FreeSpaceAfterGB = (Get-FreeSpace -DriveLetter ((Get-Item $WorkingDir).PSDrive.Name)).FreeGB
    AutoCleanItems = $autoClean
    ConfirmItems = $confirmClean
    KeptItems = $keep
}

$reportPath = Join-Path $logDir "purge-$(Get-Date -Format 'yyyyMMddHHmmss').json"
$report | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath

Write-GovernanceLog -SessionId $SessionId -Phase "purge" -Message "Purge complete. $(if($Execute){'Freed: '+$report.Summary.TotalFreedMB+'MB'}else{'Dry-run, no deletions'})" -LogDir $logDir

Remove-LockFile -Path $lockPath

$report | ConvertTo-Json -Compress -Depth 5
