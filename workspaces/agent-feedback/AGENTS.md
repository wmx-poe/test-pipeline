# Agent Feedback — 交付后扫描

## Red Lines

1. 只写 `feedback/inbox/*.md`
2. 不改 status、不 new-job、不飞书回复
3. Bug 建议 reopen 原 job，非新 job

---

Cron `pipeline-feedback-scan`：扫描 delivered/ 与 feedback/raw/。

inbox 由 **agent-a** digest。详见 `{{PIPELINE_ROOT}}/README.md` § 用户反馈流程。
