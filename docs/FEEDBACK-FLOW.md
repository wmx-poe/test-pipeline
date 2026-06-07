# 用户反馈流程

## 与 Bug 区分

| | 用户反馈 | Bug |
|---|----------|-----|
| 含义 | 建议、抱怨、体验 | 可复现缺陷、不符合验收 |
| 脚本 | `report-feedback.sh` | `report-bug.sh` |
| 文件 | `reports/user-feedback.md` | `reports/bugs.md` |
| 自动 coder | **否** | **是**（fix_needed） |

## 登记

```bash
PIPELINE_AGENT=agent-a ./scripts/report-feedback.sh <job-id> \
  --type suggestion --reason "用户希望..." --by feishu-user
```

## agent-a 分拣

1. 确认为 Bug → `report-bug.sh`
2. 新功能 → 确认后 `new-job.sh`（**唯一开 job 入口**）
3. 改 spec → 更新 draft/pending 的 spec.md
4. 仅存档 → 保留 user-feedback.md

## inbox 闭环

`agent-feedback` 生成 `feedback/inbox/*.md` → agent-a digest：

- `bug_report` → `reopen-job.sh`（**不开新 job**）
- `feature_request` → 问用户是否新需求
- `user_complaint` → 摘要；涉及缺陷则 reopen

处理完移至 `inbox/processed/`。
