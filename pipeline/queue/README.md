# 工作队列目录

状态流转（每个任务在 `pipeline-workspace/<project>/jobs/<job-id>/` 工作，编排索引在 `pipeline/jobs/<job-id>/job.md`）：

## 开 job 规则

| 用户意图 | 做法 |
|----------|------|
| **新需求** | agent-a 确认 → `new-job.sh` → `draft` → … |
| **Bug / 改已有任务 / 未完成补完** | **同一 job**：`reopen-job.sh` 或更新原 spec，**禁止** new-job |

agent-a 收到消息时先问：**新需求、Bug，还是运维？** Bug → `report-bug.sh`；运维 → `ops/inbox`（agent-om）。见 [BUG-FLOW.md](../../docs/BUG-FLOW.md)。

## 状态表

| 状态 | 位置 | 处理 Agent |
|------|------|------------|
| `draft` | workspace `status=draft` | Agent A brainstorming（用户批准前，Cron 不扫描） |
| `pending` | workspace `status=pending` | timer 推进 `designing`（须 validate-spec + integrity） |
| `designing` | 进行中 | agent-design（Stitch）；出口 `job-transition→design_done` |
| `design_done` | workspace `design/` 有产物 | timer 推进 `implementing` |
| `implementing` | 进行中 | agent-coder；出口 `job-transition→impl_done` |
| `impl_done` | 有 `implement-summary.md` | timer 推进 `verifying` |
| `verifying` | 进行中 | agent-verifier；`complete-verify` 设 verified/fix_needed |
| `verified` | verify PASS + deploy-info | 交付 → `<project>/delivered/` |
| `fix_needed` | 验证 FAIL 或 Bug | agent-coder 读 verify-feedback / bugs.md |
| `verify_paused` | 已达 10 轮仍未通过 | agent-a 飞书报告，等用户决定 |
| `verify_failed` | 用户放弃 | 人工 |
| `delivered` | `pipeline-workspace/<project>/delivered/` | agent-feedback 定期扫描 |

Agent A 通过 `skills/brainstorming/SKILL.md` 完成**新需求**分析；Bug 走 `reopen-job.sh`。

## 目录布局

```
test-pipeline/pipeline/jobs/<job-id>/job.md     # 指针（仅此文件）
pipeline-workspace/<project>/
  jobs/<job-id>/          # spec, status, design, src, reports
  delivered/<job-id>/     # 验证通过后复制
  feedback/             # raw, inbox, inbox/processed
```

验证与部署约定：[docs/VERIFICATION.md](../../docs/VERIFICATION.md)
