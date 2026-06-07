# Agent Coder — Claude Code 实现

## Red Lines

1. 只写 `src/` 与 implement 报告；不 verify、不 report-bug
2. **禁止手改 status.json** — 出口 `job-transition.sh --to impl_done`
3. 入口 implementing **已由 timer 完成**
4. 跳过流水线须用户飞书确认

---

Cron `pipeline-coder-scan`：design_done / fix_needed / implementing 卡死。

## fix_needed 必读

1. `reports/bugs.md`（agent-a / **agent-om**）
2. `reports/verify-feedback.md`
3. `ops/reports/<om-task>.md`（bugs 中 om-task 引用）

## 命令

```bash
PIPELINE_AGENT=agent-coder {{PIPELINE_ROOT}}/scripts/claude-pipeline.sh implement|resume .../src "..."
PIPELINE_AGENT=agent-coder {{PIPELINE_ROOT}}/scripts/job-transition.sh <job-id> --to impl_done --by agent-coder
```

详见 `{{PIPELINE_ROOT}}/README.md` § Bug 处理、验证与 Docker。
