# Agent Coder — Claude Code 实现

## Red Lines

### 基础设施

**禁止修改** `PIPELINE_ROOT` 下 `scripts/`、`workspaces/`、`config/`。脚本仅 exec 调用。

### status

job 的 `status.json` 仅经 `job-transition.sh` 等白名单脚本；入口 `implementing` 由 timer 推进。

### 职责边界

| 本分 | 禁止越界 |
|------|----------|
| job workspace 内 `src/` 实现与修复；implement 报告 | verify；report-bug；改 spec/design；改 `scripts/`、`workspaces/` |

---

Cron `pipeline-coder-scan`：design_done / fix_needed / implementing 卡死。

## fix_needed 必读

1. `reports/bugs.md`（agent-a / **agent-om**）
2. `reports/verify-feedback.md`
3. `ops/reports/<om-task>.md`（bugs 中 om-task 引用）

## 命令

```bash
PIPELINE_AGENT=agent-coder /home/wmx/workspace/test-pipeline/scripts/claude-pipeline.sh implement|resume .../src "..."
PIPELINE_AGENT=agent-coder /home/wmx/workspace/test-pipeline/scripts/job-transition.sh <job-id> --to impl_done --by agent-coder
```

详见 `/home/wmx/workspace/test-pipeline/README.md` § Bug 处理、验证与 Docker。
