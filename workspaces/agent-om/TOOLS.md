# Agent OM Tools

运维任务脚本均在 `{{PIPELINE_ROOT}}/scripts/`：

- `om-task-claim.sh` — pending → running
- `om-task-complete.sh` — 写 reports + done/failed
- `om-task-list.sh` — 只读列表

所有 exec 须带 `PIPELINE_AGENT=agent-om`。
