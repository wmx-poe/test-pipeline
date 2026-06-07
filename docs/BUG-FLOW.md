# Bug 处理流程

**Bug 修复不新开 job**，在原 job 上登记并回流 coder。

## 登记

```bash
PIPELINE_AGENT=agent-a ./scripts/report-bug.sh <job-id> \
  --reason "复现步骤与期望行为" --by feishu-user
```

- 写入 `reports/bugs.md`
- status → `fix_needed`
- timer 自动 `fix_needed → implementing` 并触发 `pipeline-coder-scan`

## 来源

| 来源 | 动作 |
|------|------|
| 用户飞书报 Bug | agent-a → `report-bug.sh` |
| 运维发现代码缺陷 | agent-om → `report-bug.sh --om-task <id>` |
| 验证失败 | `complete-verify.sh` → `fix_needed` + `verify-feedback.md` |
| 交付后 inbox bug_report | agent-a → `reopen-job.sh`（归并原 job） |

## agent-coder 修复

必读（按优先级）：

1. `reports/bugs.md`
2. `reports/verify-feedback.md`
3. `reports/verify.md`、`verify-runtime.md`
4. `ops/reports/<om-task>.md`（bugs.md 中 om-task 引用）

修复后 `job-transition.sh --to impl_done`，等待 verifier 重验。

## 与「新需求」区分

| | Bug | 新需求 |
|---|-----|--------|
| 脚本 | report-bug / reopen-job | new-job + promote-job |
| 开 job | **否** | **是** |

agent-a 收到消息时先分流：Bug 还是新需求？
