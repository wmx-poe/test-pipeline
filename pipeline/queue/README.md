# 工作队列目录

状态流转（每个任务在 `pipeline-workspace/<project>/jobs/<job-id>/` 工作，编排索引在 `pipeline/jobs/<job-id>/job.md`）：

## 开 job 规则

| 用户意图 | 做法 |
|----------|------|
| **新需求** | agent-a 确认 → `new-job.sh` → `draft` → … |
| **Bug / 改已有任务 / 未完成补完** | **同一 job**：`reopen-job.sh` 或更新原 spec，**禁止** new-job |

agent-a 收到消息时先问：**新需求，还是已有任务/Bug？**

## 状态表

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
| `fix_needed` | 验证 FAIL 或用户 Bug | agent-coder 读 verify-feedback / user-feedback |
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
