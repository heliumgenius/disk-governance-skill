# tests/test-rules.ps1
BeforeAll {
    $rulesPath = "$PSScriptRoot\..\rules\default.json"
}

Describe "default.json validation" {
    It "File exists" {
        Test-Path $rulesPath | Should -Be $true
    }

    It "Is valid JSON" {
        $content = Get-Content $rulesPath -Raw
        $parsed = $content | ConvertFrom-Json
        $parsed | Should -Not -BeNullOrEmpty
    }

    It "Has required top-level keys" {
        $content = Get-Content $rulesPath -Raw
        $parsed = $content | ConvertFrom-Json
        $parsed.auto_delete_patterns | Should -Not -BeNullOrEmpty
        $parsed.protected_patterns | Should -Not -BeNullOrEmpty
        $parsed.agent_runtime_paths | Should -Not -BeNullOrEmpty
    }

    It "Has minimum free space threshold" {
        $content = Get-Content $rulesPath -Raw
        $parsed = $content | ConvertFrom-Json
        $parsed.min_free_space_gb | Should -BeGreaterThan 0
    }
}
