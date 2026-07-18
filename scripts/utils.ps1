# utils.ps1 — Shared helpers for disk-governance scripts

function New-SessionId {
    return [System.Guid]::NewGuid().ToString()
}

function Get-Timestamp {
    return (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
}

function Get-DirectorySize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    return [long]$size
}

function Get-FileTree {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            [PSCustomObject]@{
                Path = $_.FullName
                Size = $_.Length
                LastWriteTime = $_.LastWriteTime
                Extension = $_.Extension
            }
        }
}

function Get-FreeSpace {
    param([string]$DriveLetter = "C")
    $drive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if (-not $drive) { return @{FreeGB = -1; TotalGB = -1} }
    return @{
        FreeGB = [math]::Round($drive.Free / 1GB, 2)
        TotalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    }
}

function Write-GovernanceLog {
    param([string]$SessionId, [string]$Phase, [string]$Message, [string]$LogDir)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $logPath = Join-Path $LogDir "governance.log"
    $entry = @{
        Timestamp = Get-Timestamp
        SessionId = $SessionId
        Phase = $Phase
        Message = $Message
    } | ConvertTo-Json -Compress
    Add-Content -Path $logPath -Value $entry
}

function Remove-NulFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Write-Warning "Attempting to delete reserved name file: $Path"
    try {
        $file = [System.IO.File]::Open("\\$Path", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $file.Close()
        [System.IO.File]::Delete("\\$Path")
    } catch {
        try {
            & cmd /c "del /f /q `"$Path`"" 2>$null
        } catch {
            Write-Warning "Failed to delete nul file: $Path. Try using WSL: wsl rm -f '$($Path -replace '\\', '/')'"
        }
    }
}

function Test-IsWindows {
    return $env:OS -eq "Windows_NT"
}

function New-LockFile {
    param([string]$Path)
    if (Test-Path $Path) {
        $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $lock = $content | ConvertFrom-Json
            $age = [DateTime]::Now - [DateTime]$lock.Timestamp
            if ($age.TotalMinutes -lt 60) {
                throw "Another governance session is active (PID: $($lock.PID), started: $($lock.Timestamp))"
            } else {
                Write-Warning "Stale lock file found (age: $($age.TotalMinutes) min). Overriding."
            }
        }
    }
    $lockInfo = @{
        PID = [System.Diagnostics.Process]::GetCurrentProcess().Id
        Timestamp = (Get-Date -Format "o")
        Hostname = $env:COMPUTERNAME
    } | ConvertTo-Json
    Set-Content -Path $Path -Value $lockInfo
}

function Remove-LockFile {
    param([string]$Path)
    if (Test-Path $Path) { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue }
}

function Resolve-PathSafe {
    param([string]$Path)
    if ($Path.Length -gt 240 -and $env:OS -eq "Windows_NT") {
        if (-not $Path.StartsWith("\\?\")) {
            return "\\?\$Path"
        }
    }
    return $Path
}

function Convert-PatternToRegex {
    param([string]$Pattern)
    $expanded = [System.Environment]::ExpandEnvironmentVariables($Pattern)
    $normalized = $expanded.Replace('\', '/')
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $normalized.Length) {
        $c = $normalized[$i]
        if ($c -eq '*' -and $i + 1 -lt $normalized.Length -and $normalized[$i + 1] -eq '*') {
            if ($i + 2 -lt $normalized.Length -and $normalized[$i + 2] -eq '/') {
                $sb.Append('(.*[/\\])?') | Out-Null
                $i += 3
            } else {
                $sb.Append('.*') | Out-Null
                $i += 2
            }
        } elseif ($c -eq '*') {
            $sb.Append('[^/]*') | Out-Null
            $i += 1
        } elseif ($c -eq '?') {
            $sb.Append('[^/]') | Out-Null
            $i += 1
        } elseif ($c -eq '/') {
            $sb.Append('[/\\]') | Out-Null
            $i += 1
        } else {
            $sb.Append([regex]::Escape($c.ToString())) | Out-Null
            $i += 1
        }
    }
    return $sb.ToString()
}
