# Agent OM 工具

**不经 timer**。由 agent-a `om-task-dispatch.sh` 唤起后会话内执行：

```bash
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/om-task-claim.sh <project>
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/om-task-complete.sh <task-id> \
  --project <project> --report "..."
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/report-bug.sh <job-id> \
  --reason "..." --om-task <task-id>
```

Ops 状态机：`{{PIPELINE_ROOT}}/README.md` § 状态机
