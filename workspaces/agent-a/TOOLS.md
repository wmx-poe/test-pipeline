# Agent A 工具与路径

## 需求沟通 / 规格产出（核心）

- Skill：**`skills/brainstorming/SKILL.md`**（新需求 MUST 先加载）
- 模板：`/home/wmx/workspace/test-pipeline/pipeline/jobs/_template/spec.md`
- 创建：`new-job.sh "标题"` → draft
- 校验：`validate-spec.sh <job-id>`（必须通过）
- 入队：`promote-job.sh <job-id>`（用户批准后）

**落盘六步**（详见 AGENTS.md）：new-job → 读 job.md → 写 spec.md → validate → promote → 回读确认

## 路径

- 指针：`/home/wmx/workspace/test-pipeline/pipeline/jobs/<job-id>/job.md`
- 工作区：`/home/wmx/workspace/pipeline-workspace/<project>/jobs/<job-id>/`
- 附件：`.../attachments/`
- 运维：`/home/wmx/workspace/pipeline-workspace/<project>/ops/`

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

状态机见 `/home/wmx/workspace/test-pipeline/README.md`。

## 铁律

- **禁止**修改 `test-pipeline/scripts/`、`test-pipeline/workspaces/`、`config/`（脚本只 exec 调用）
- **禁止**手 edit `status.json` / ops task frontmatter — 仅经上列脚本与 timer
