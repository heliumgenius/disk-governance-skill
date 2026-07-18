# tests/test-snapshot.ps1
BeforeAll {
    $scriptDir = "$PSScriptRoot\..\scripts"
}

Describe "snapshot.ps1 validation" {
    It "Script exists and is valid PowerShell" {
        $path = Join-Path $scriptDir "snapshot.ps1"
        Test-Path $path | Should -Be $true

        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It "Has required parameters" {
        $path = Join-Path $scriptDir "snapshot.ps1"
        $scriptBlock = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $params = $scriptBlock.ParamBlock.Parameters.Name.Value
        "WorkingDir" -in $params | Should -Be $true
    }
}
