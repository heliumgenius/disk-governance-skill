# Disk Governance Skill

A cc-switch compatible skill for **three-phase disk governance** — snapshot, patrol, and purge — designed for AI coding agent workspaces (opencode, Claude Code).

## What

Disk Governance automates the lifecycle of disk space in agent workspaces:

| Phase | Command | What it does |
|-------|---------|-------------|
| **Snapshot** | `disk-governance snapshot` | Records current state of all project directories — size, file count, age, free space |
| **Patrol** | `disk-governance patrol` | Continuously monitors disk usage, identifies orphaned or bloated project directories |
| **Purge** | `disk-governance purge` | Recovers disk space by deleting confirmed files (auto-delete patterns) or asking for confirmation (confirm patterns) |

## Install

```powershell
# Clone the repo
git clone https://github.com/<your-org>/disk-governance-skill.git
cd disk-governance-skill

# (Optional) Symlink into your cc-switch skills directory
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude\skills\disk-governance" -Target "$pwd"
```

## Quick Start

```powershell
# Take a snapshot of all projects
.\disk-governance.ps1 snapshot

# Patrol for candidates
.\disk-governance.ps1 patrol

# Purge with confirmation
.\disk-governance.ps1 purge

# Quick purge (skips confirm patterns, only deletes auto-delete patterns)
.\disk-governance.ps1 purge --auto-only
```

## Configure

Edit `config.yaml` or create `~/.config/disk-governance/config.yaml`:

```yaml
min_free_space_gb: 10
patrol_interval_minutes: 30
idle_project_days: 90
orphan_process_cleanup: true
```

Custom cleanup rules go in `rules/` (see `rules/default.json` for reference).

## Safety

- **Read-only by default.** Snapshot and patrol never write or delete.
- **Two-tier deletion.** Auto-delete patterns run without confirmation; confirm patterns require user approval.
- **Protected patterns** (`**/.git/**`, `**/CLAUDE.md`, etc.) are never touched.
- **Dry-run mode.** Pass `--dry-run` to any purge command to preview without deleting.

## Windows Notes

- Uses PowerShell 5.1+ (built into Windows 10/11).
- Temp paths resolve via `$env:TEMP` and `$env:LOCALAPPDATA`.
- Long path support required for `node_modules` traversal — enable via Group Policy or `fsutil behavior set disable8dot3 1`.

## Uninstall

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude\skills\disk-governance"
# Or if cloned standalone:
Remove-Item -Recurse -Force "$env:USERPROFILE\disk-governance-skill"
```
