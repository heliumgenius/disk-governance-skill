# Contributing

## Adding Cleanup Rules

1. Add patterns to `rules/default.json` under the appropriate section:
   - `auto_delete_patterns` — safe-to-delete patterns (caches, build artifacts, temp files)
   - `confirm_patterns` — patterns that require user confirmation
   - `protected_patterns` — patterns that must never be deleted
2. Add corresponding Pester tests in `tests/`
3. Run tests: `Invoke-Pester -Path tests/`

## Testing

This project uses **Pester** (PowerShell testing framework).

```powershell
# Run all tests
Invoke-Pester

# Run specific test file
Invoke-Pester -Path tests/Test-Rules.tests.ps1
```

## Submitting PRs

1. Branch from `main`
2. Keep changes focused — one PR per feature or fix
3. Include tests for new functionality
4. Run the full test suite before opening
5. Update `CHANGELOG.md` under `[Unreleased]`
6. Open PR against `main`

## Code Style

- PowerShell: follow PSScriptAnalyzer rules
- JSON/YAML: 2-space indentation
- Keep functions small and composable
- Use verbose logging (`Write-Verbose`) for debugging output
