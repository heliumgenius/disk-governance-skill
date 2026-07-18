# Disk Governance Skill — 磁盘治理技能

AI 编程助手（opencode、Claude Code）工作目录的**三阶段磁盘治理**：快照 → 巡检 → 清理。防止 AI agent 在工作目录留下垃圾文件。

## 三阶段工作流

| 阶段 | 命令 | 做什么 |
|------|------|--------|
| **快照** (Snapshot) | `scripts/snapshot.ps1` | 记录工作目录的初始状态——文件列表、大小、空闲空间 |
| **巡检** (Patrol) | `scripts/patrol.ps1` | 对比快照，发现新增文件，按规则分类为 auto / confirm |
| **清理** (Purge) | `scripts/purge.ps1` | 默认 dry-run；加 `-Execute` 后删除 auto 文件，保留 confirm 文件等用户确认 |

### 规则分类

- **auto_delete_patterns** — 自动删除，无需确认（`.tmp`、`.bak`、`node_modules/`、`__pycache__/` 等）
- **confirm_patterns** — 需要人工确认（`.md`、`.json`、`.log` 等）
- **protected_patterns** — 永不触碰（`.git/`、`CLAUDE.md`、`.env*` 等）

规则文件：`rules/default.json`

## 安装

```powershell
# 克隆仓库
git clone https://github.com/heliumgenius/disk-governance-skill.git
cd disk-governance-skill

# 推荐：通过 cc-switch 安装
cc-switch install skill ./disk-governance-skill
```

cc-switch 会自动将 skill 链接到 `~/.config/opencode/skills/disk-governance/`。

## 快速开始

```powershell
# 阶段一：快照工作目录
.\scripts\snapshot.ps1 -WorkingDir C:\MyProject
# 返回 SessionId（记录到 JSON）

# 阶段二：巡检新增文件
.\scripts\patrol.ps1 -SessionId <SessionId> -WorkingDir C:\MyProject
# 返回异常列表（auto / confirm 分类）

# 阶段三：预览清理（dry-run 模式，不删文件）
.\scripts\purge.ps1 -SessionId <SessionId> -WorkingDir C:\MyProject

# 确认后执行清理
.\scripts\purge.ps1 -SessionId <SessionId> -WorkingDir C:\MyProject -Execute
```

### 完整一键示例

```powershell
$r = .\scripts\snapshot.ps1 -WorkingDir $pwd | ConvertFrom-Json
$sid = $r.SessionId
# ... 让 AI 工作 ...
.\scripts\patrol.ps1 -SessionId $sid -WorkingDir $pwd
.\scripts\purge.ps1 -SessionId $sid -WorkingDir $pwd
.\scripts\purge.ps1 -SessionId $sid -WorkingDir $pwd -Execute
```

## 在 AI Agent 中使用

本 skill 通过 cc-switch 集成到 AI agent 的工作流中。Agent 会自动：

1. 开始任务前 → 执行 `snapshot.ps1`
2. 任务执行期间定时 → 执行 `patrol.ps1`
3. 任务完成后 → 执行 `purge.ps1`（dry-run 确认后加 `-Execute`）

Agent 读取 `SKILL.md` 中的指令来自动执行这三个阶段。

## 配置

编辑 `rules/default.json` 自定义清理规则：

```json
{
  "auto_delete_patterns": [
    "**/*.tmp", "**/*.bak", "**/node_modules/**", "**/__pycache__/**"
  ],
  "confirm_patterns": [
    "**/*.md", "**/*.json", "**/*.log"
  ],
  "protected_patterns": [
    "**/.git/**", "**/CLAUDE.md", "**/.env*"
  ],
  "max_file_size_mb": 50,
  "min_free_space_gb": 5
}
```

## 安全机制

- **只读优先**：快照和巡检不写不删
- **两级删除**：auto 模式自动删除，confirm 模式需要人工确认
- **保护模式**：`.git/`、`CLAUDE.md` 等文件永不触碰
- **Dry-run 默认**：不加 `-Execute` 时只预览不删除
- **并发锁**：`governance.lock` 防止同一 Session 并行清理

## 测试

```powershell
# 运行 Pester 测试
.\tests\test-utils.ps1
.\tests\test-snapshot.ps1
.\tests\test-rules.ps1
```

## 跨平台

| 平台 | 状态 |
|------|------|
| Windows (PowerShell 5.1+) | ✅ 原生支持 |
| macOS | ⚠️ 脚本基础兼容，未完整测试 |
| Linux | ⚠️ 脚本基础兼容，未完整测试 |

## 许可证

MIT

## 项目地址

https://github.com/heliumgenius/disk-governance-skill
