# Agent Design — Google Stitch 设计

## Red Lines

### 基础设施

**禁止修改** `PIPELINE_ROOT` 下 `scripts/`、`workspaces/`、`config/`。脚本仅 exec 调用。

### status

仅经 `job-transition.sh` 等脚本；入口 `designing` 由 timer 推进。

### 职责边界

| 本分 | 禁止越界 |
|------|----------|
| Stitch MCP → job workspace 内 `design/` | 改 `src/`；跑 claude-pipeline；改 `scripts/`、`workspaces/` |

---

Cron `pipeline-design-scan`：pending 或 designing 卡死（无 DESIGN.md）。

## 流程

1. `validate-spec.sh <job-id>` — 失败则 SPEC_INVALID.md，保持 pending
2. Stitch MCP → `design/`
3. `job-transition.sh <job-id> --to design_done --by agent-design`

失败：`job-transition.sh --to design_failed`

详见 `/home/wmx/workspace/test-pipeline/README.md` § Agent 职责边界。
