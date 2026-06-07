---
name: brainstorming
description: "仅当用户确认是【新需求】时 MUST 加载本 skill。Bug/改已有任务不得调用 new-job.sh。通过多轮澄清产出 spec.md，用户批准后再入队（status=pending）。"
---

# Brainstorming — 需求分析与规格产出

将用户意图转化为可被下游 Agent（design → coder → verifier）无歧义执行的 `spec.md`。

<HARD-GATE>
本 skill **仅用于新需求**（用户已确认不是 Bug/改已有 job）。

- Bug、验证失败、交付后缺陷、补完未完成项 → 使用原 job + `reopen-job.sh`，**禁止** new-job.sh
- 在用户明确批准设计之前：
- 不得将 `status.json` 设为 `pending`
- 不得修改 `src/`、不得调用 Stitch / Claude Code
- 不得声称「流水线已接手」
</HARD-GATE>

## 产出路径

- 任务索引：`{{PIPELINE_ROOT}}/pipeline/jobs/<job-id>/job.md`（指针，含 workspace 路径）
- 任务工作区：`{{WORKSPACE_ROOT}}/<project>/jobs/<job-id>/`（实际内容）
- 规格文件：workspace 内 `spec.md`（按 `pipeline/jobs/_template/spec.md` 结构）
- 状态文件：workspace 内 `status.json`
  - 头脑风暴进行中：`status: "draft"`
  - 用户批准后：`status: "pending"`

`job-id` 格式：`job-YYYYMMDD-HHMMSS`。项目名 `<project>` 由创建时 title 自动 slug 化，写入指针与 status.json。

## 流程（按顺序）

1. **探索上下文** — 确认是新需求；阅读近期 job 指针与各 project 工作区
2. **创建 draft 任务** — **仅新需求** 调用 `new-job.sh`
3. **澄清问题** — 飞书一次只问一个问题；优先选择题；聚焦目的、约束、验收标准
4. **方案对比** — 给出 2–3 种方案、权衡与推荐（写在飞书摘要中，最终写入 spec）
5. **呈现设计** — 按复杂度分节（架构、组件、数据流、错误处理、测试）；每节后询问是否 OK
6. **写入 spec.md** — 写入 **workspace** 内（见下方「落盘步骤」），填完整模板各节
7. **校验** — 运行 `{{PIPELINE_ROOT}}/scripts/validate-spec.sh <job-id>`；失败则修正后重跑
8. **自检** — 扫描 TBD/矛盾/歧义/范围过大，当场修正
9. **用户审阅** — 飞书发送 spec 摘要 + job-id + project，请用户确认或修改
10. **入队** — 用户批准后运行 `{{PIPELINE_ROOT}}/scripts/promote-job.sh <job-id>`，再 `read` workspace 内 `status.json` 确认 `status=pending`

## 落盘步骤（MUST，不可跳过）

```bash
# 1) 创建 draft（写指针 + workspace）
{{PIPELINE_ROOT}}/scripts/new-job.sh "任务标题"

# 2) 读 job.md 获取 workspace 路径，写入 spec.md（write/edit/exec — 禁止只在飞书发文字）
# 3) 校验
{{PIPELINE_ROOT}}/scripts/validate-spec.sh <job-id>

# 4) 用户批准后再入队
{{PIPELINE_ROOT}}/scripts/promote-job.sh <job-id>
```

**终点是 `status=pending`，不是实现。** 实现由 agent-design / agent-coder / agent-verifier 负责。

## 澄清原则

- 一次一问，不要连发多个问题
- 范围过大时先拆子项目，只对第一个子项目走完整流程
- YAGNI：砍掉非必要功能
- 简单需求设计可很短，但仍须走确认闸门

## 视觉辅助（可选）

若涉及 UI/布局/架构图，可询问用户是否使用 **diagram-maker** 或 **canvas** skill 展示对比图。用户拒绝则用文字继续。

## spec.md 必填节

标题可带编号或说明，例如 `## 1. 项目目标`、`## 11. 验收标准（UAT）`。  
以 `validate-spec.sh` 通过为准，不必机械套用 `_template/spec.md` 的 exact 标题。

| 语义 | 示例标题 | 内容 |
|------|----------|------|
| 目标 | `## 目标` / `## 1. 项目目标` | 用户要达成什么 |
| 验收标准 | `## 验收标准` / `## 11. 验收标准（UAT）` | 可勾选 `- [ ]` 或编号列表 `1.` |
| 背景/约束 | `## 背景知识` / `## 已确认约束` | 约束、现有系统、依赖 |
| 需求来源 | `## 用户原始输入` / `## 已确认约束` | 摘要或转写 |
| 方案/架构 | `## 方案对比` / `## 总体架构设计` | 方案权衡或架构说明 |
| 设计摘要 | `## 设计摘要` / `## 功能需求` | 组件、数据流、测试要点 |

## 自检清单

1. 有无 TBD、空节、模糊验收标准？
2. 各节是否自相矛盾？
3. 范围是否适合单次流水线（否则拆分）？
4. 需求是否存在两种合理解读？若有，选定一种写死。
5. **`validate-spec.sh` 是否已通过？** 未通过则不得进入用户审阅或入队。
6. **workspace 内 `spec.md` 是否与飞书摘要一致？** 用 `read` 回读核对。

## 用户批准后话术（示例）

> 任务 `{job-id}`（项目 `{project}`）已确认，规格已锁定。流水线将依次执行：Stitch 设计 → Claude Code 实现 → 验证。您可随时回复 job-id 查询进度。

## 续聊与修改

- 用户对 **draft** 任务回复修改意见：更新 workspace 内 `spec.md`，保持 `draft`
- 用户说「可以了」「确认」「开始吧」等明确批准：才设 `pending`
- 已 `pending` 的任务：在原 job 更新 spec（`## 变更记录`），**不要** new-job.sh
- Bug / 改已有功能：走 `reopen-job.sh`，**不要** new-job.sh
