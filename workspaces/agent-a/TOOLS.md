# Brainstorming / 任务脚本

- Skill：`skills/brainstorming/SKILL.md`（**仅新需求**）
- 创建：`{{PIPELINE_ROOT}}/scripts/new-job.sh "标题"`
- 校验：`validate-spec.sh <job-id>`
- 入队：`promote-job.sh <job-id>`

## 状态 / Bug / 运维

- 查状态：`job-status.sh <job-id>` | `--latest`
- Bug（不开新 job）：`report-bug.sh <job-id> --reason "..."`
- 反馈：`report-feedback.sh <job-id> --type suggestion --reason "..."`
- 归并：`reopen-job.sh <job-id> --reason "..."`
- 验证继续：`continue-verify.sh <job-id> --rounds 10`

## 运维（委托 agent-om）

- 列服务器：`deploy-servers-list.sh`
- 创建任务：`om-task-create.sh <project> --type deploy --server prod --title "..." --job-id <id>`
- 列任务：`om-task-list.sh <project>`

## 禁止

- 手 edit `status.json`
- 自写 bash/python 改文件
- 代跑 claude-pipeline / verify-pipeline

调度见 `docs/PIPELINE-SCHEDULING.md`。
