# Agent A 工具与路径

## 需求沟通 / 规格产出（核心）

- Skill：**`skills/brainstorming/SKILL.md`**（新需求 MUST 先加载）
- 模板：`{{PIPELINE_ROOT}}/pipeline/jobs/_template/spec.md`
- 创建：`new-job.sh "标题"` → draft
- 校验：`validate-spec.sh <job-id>`（必须通过）
- 入队：`promote-job.sh <job-id>`（用户批准后）

**落盘六步**（详见 AGENTS.md）：new-job → 读 job.md → 写 spec.md → validate → promote → 回读确认

## 路径

- 指针：`{{PIPELINE_ROOT}}/pipeline/jobs/<job-id>/job.md`
- 工作区：`{{WORKSPACE_ROOT}}/<project>/jobs/<job-id>/`
- 附件：`.../attachments/`
- 运维：`{{WORKSPACE_ROOT}}/<project>/ops/`

## 状态 / Bug / 反馈

- 查状态：`job-status.sh <job-id>` | `--latest`
- Bug：`report-bug.sh <job-id> --reason "..."`
- 反馈：`report-feedback.sh <job-id> --type suggestion --reason "..."`
- 归并：`reopen-job.sh <job-id> --reason "..."`
- 验证继续：`continue-verify.sh <job-id> --rounds 10`

## 运维（直驱 agent-om，不经 timer）

- 创建：`om-task-create.sh <project> --type ... --title "..."`
- **唤起**：`om-task-dispatch.sh <project> <task-id>`（create 后必须执行）
- 取消：`om-task-cancel.sh <task-id> --project <project>`
- 列任务：`om-task-list.sh <project>`

状态机见 `{{PIPELINE_ROOT}}/README.md`。

## 禁止

- 手 edit `status.json`
- 只在飞书发 spec 不落盘
- 自写 bash/python 改文件
- 代跑 claude-pipeline / verify-pipeline / Stitch

调度见 `{{PIPELINE_ROOT}}/README.md` § Timer 调度。
