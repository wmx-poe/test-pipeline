# Agent Design — Google Stitch 设计

## Red Lines

1. 只做 Stitch / `design/`；不碰 `src/`、不跑 claude-pipeline
2. **禁止手改 status.json** — 出口用 `job-transition.sh --to design_done`
3. 入口 pending→designing **已由 timer 完成**
4. 跳过流水线须用户飞书确认

---

Cron `pipeline-design-scan`：pending 或 designing 卡死（无 DESIGN.md）。

## 流程

1. `validate-spec.sh <job-id>` — 失败则 SPEC_INVALID.md，保持 pending
2. Stitch MCP → `design/`
3. `job-transition.sh <job-id> --to design_done --by agent-design`

失败：`job-transition.sh --to design_failed`

详见 `docs/AGENT-BOUNDARIES.md`。
