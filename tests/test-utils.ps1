# tests/test-utils.ps1
BeforeAll {
    . "$PSScriptRoot\..\scripts\utils.ps1"
}

Describe "New-SessionId" {
    It "Generates a non-empty GUID" {
        $id = New-SessionId
        $id | Should -Not -BeNullOrEmpty
        $id.Length | Should -Be 36
    }

    It "Generates unique IDs" {
        $id1 = New-SessionId
        $id2 = New-SessionId
        $id1 | Should -Not -Be $id2
    }
}

Describe "Get-DirectorySize" {
    It "Returns 0 for non-existent path" {
        $size = Get-DirectorySize -Path "Z:\nonexistent"
        $size | Should -Be 0
    }

    It "Returns correct size for existing directory" {
        $tmpDir = Join-Path $env:TEMP "test-gov-$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        Set-Content -Path (Join-Path $tmpDir "test.txt") -Value "hello"
        $size = Get-DirectorySize -Path $tmpDir
        $size | Should -Be 5
        Remove-Item -Path $tmpDir -Force -Recurse
    }
}

Describe "Get-FreeSpace" {
    It "Returns free space for C: drive" {
        $space = Get-FreeSpace -DriveLetter "C"
        $space.FreeGB | Should -BeGreaterThan 0
        $space.TotalGB | Should -BeGreaterThan 0
    }

    It "Returns -1 for invalid drive" {
        $space = Get-FreeSpace -DriveLetter "X"
        $space.FreeGB | Should -Be -1
    }
}

Describe "Test-IsWindows" {
    It "Returns true on Windows" {
        Test-IsWindows | Should -Be $true
    }
}
