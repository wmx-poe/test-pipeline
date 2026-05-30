# 工作队列目录

状态流转（每个任务一个子目录 `pipeline/jobs/<job-id>/`）：

| 状态 | 目录 | 处理 Agent |
|------|------|------------|
| `draft` | `jobs/*/status=draft` | Agent A brainstorming（用户批准前，Cron 不扫描） |
| `pending` | `jobs/*/status=pending` | 用户批准 → Design 扫描 |
| `designing` | 进行中 | agent-design |
| `design_done` | `design/` 有产物 | agent-coder 扫描 |
| `implementing` | 进行中 | agent-coder |
| `impl_done` | `src/` 有代码 | agent-verifier 扫描 |
| `verifying` | 进行中 | agent-verifier |
| `verified` | `reports/verify.md` | 交付 → `delivered/` |
| `delivered` | `delivered/` | agent-feedback 定期扫描 |

Agent A 通过 `skills/brainstorming/SKILL.md` 完成需求分析，写入 `jobs/<job-id>/spec.md`；用户批准后 `status` 从 `draft` 变为 `pending`。
