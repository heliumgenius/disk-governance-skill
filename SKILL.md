---
name: disk-governance
description: |
  Three-phase disk governance for AI agent sessions. Prevents agents from
  leaving garbage files on disk. Use when starting any task that writes files
  — projects, data processing, code generation, web scraping, file manipulation.
  Automatically runs snapshot → patrol → purge for every session.
  Do NOT use for read-only tasks, pure terminal operations, or when you want
  to intentionally leave files behind.
metadata:
  cc-switch:
    repoOwner: "heliumgenius"
    repoName: "disk-governance-skill"
    repoBranch: "main"
    remotePath: "SKILL.md"
license: MIT
---

# Disk Governance Skill

## When to Use

**Automatic.** This skill activates on every task that creates files:
- Starting a new project
- Modifying existing codebase
- Data scraping / analysis
- File generation or conversion
- Installing dependencies

**Do NOT use** for:
- Read-only queries ("what does this function do?")
- Pure terminal operations ("run this command")
- Sessions where you intentionally keep temp files

## Safety Rules (Ironclad)

1. **Never touch** files matching `protected_patterns` in `rules/default.json`
2. **Never delete** outside `$HOME` without explicit user approval
3. **Phase 2 Patrol is report-only by default** — no auto-deletion during active session
4. **Phase 3 Purge** requires cleanup report approval before execution
5. **Orphan process cleanup** is opt-in (`orphan_process_cleanup: true`)
6. **Phase 1 aborts** if free disk space < `min_free_space_gb` and user doesn't OK it
7. **Self-cleanup**: all `.disk-governance/` artifacts deleted after Phase 3

## Three-Phase Workflow

### Phase 1: Snapshot — Run BEFORE any file operations

1. Determine working scope
2. Run `scripts/snapshot.ps1 -WorkingDir "<scope>"`
3. Check output for warnings (low disk space)
4. Present free space status to user
5. Store returned session ID for next phases

### Phase 2: Patrol — Run DURING execution

Trigger conditions:
- Every `patrol_interval_minutes` (default: 15) elapsed
- After any tool call that wrote >10MB to disk
- Before starting a subagent or parallel task

Run `scripts/patrol.ps1 -SessionId "<id>" -WorkingDir "<scope>"`

If patrol finds anomalies:
- Report them to user conversationally
- For 🟢 items: "Found some temp files, I'll clean those up."
- For 🟡 items: "Found unexpected files — should I keep or remove?"
- Never auto-delete during active session

### Phase 3: Purge — Run WHEN TASK IS COMPLETE

1. Run `scripts/purge.ps1 -SessionId "<id>" -WorkingDir "<scope>"`
2. Present cleanup report to user:
   - 🟢 Auto-cleaned files (list with sizes)
   - 🟡 Needs review (list each with context of what created it)
   - 🔴 Preserved files
3. Wait for user approval before executing deletions
4. After user approves, run purge again with `-Execute`
5. Report freed space
6. Clean up `.disk-governance/` directory

## Orphan Process Cleanup (opt-in)

If `orphan_process_cleanup: true` in config:

```powershell
# List orphan processes (runs as part of patrol)
scripts/patrol.ps1 -DetectOrphans

# Kill confirmed orphans (manual step, never auto)
# user reviews list, then: Stop-Process -Id <pid> -Force
```

Detection patterns:
- `tmpclaude*` — orphaned Claude Code subprocesses
- `playwright*mcp*` — orphaned MCP browser instances
- `node*mcp*` — orphaned MCP Node servers
- Processes running >30 minutes with no parent session

## Configuration

Per-user config at `~/.config/disk-governance/config.yaml` overrides `rules/default.json`.

Inline overrides in conversation phrase:
- "No patrol for this task" → skip Phase 2
- "Keep all my temp files" → skip Phase 3 auto-clean
- "Deep clean" → also scan agent runtime paths
