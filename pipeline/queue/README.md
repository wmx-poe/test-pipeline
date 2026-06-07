# 工作队列目录

状态流转（每个任务在 `pipeline-workspace/<project>/jobs/<job-id>/` 工作，编排索引在 `pipeline/jobs/<job-id>/job.md`）：

| 状态 | 位置 | 处理 Agent |
|------|------|------------|
| `draft` | workspace `status=draft` | Agent A brainstorming（用户批准前，Cron 不扫描） |
| `pending` | workspace `status=pending` | 用户批准 → Design 扫描 |
| `designing` | 进行中 | agent-design |
| `design_done` | workspace `design/` 有产物 | agent-coder 扫描 |
| `implementing` | 进行中 | agent-coder |
| `impl_done` | workspace `src/` 有代码 | agent-verifier 扫描 |
| `verifying` | 进行中 | agent-verifier（先 verify-pipeline + Claude verify） |
| `verified` | verify PASS + deploy-info | 交付 → `<project>/delivered/` |
| `fix_needed` | verify FAIL，待修复 | agent-coder 读 verify-feedback.md |
| `verify_paused` | 本轮 10 次验证均未通过 | agent-a 通知用户，continue-verify |
| `delivered` | `pipeline-workspace/<project>/delivered/` | agent-feedback 定期扫描 |

Agent A 通过 `skills/brainstorming/SKILL.md` 完成需求分析，写入 workspace 内 `spec.md`；用户批准后 `status` 从 `draft` 变为 `pending`。

## 目录布局

```
test-pipeline/pipeline/jobs/<job-id>/job.md     # 指针（仅此文件）
pipeline-workspace/<project>/
  jobs/<job-id>/          # spec, status, design, src, reports（进行中）
  delivered/<job-id>/     # 验证通过后复制（与 jobs 平级）
  feedback/               # raw, inbox, inbox/processed（与 delivered 平级）
  ops/                    # agent-om（agent-a 直驱，不经 timer）
    tasks/                # pending → in_progress → done
    reports/
```

Job 与 Ops 状态机见 [README.md](../../README.md#状态机)。

验证与部署约定：[README.md § 验证与 Docker](../../README.md#验证与-docker)
