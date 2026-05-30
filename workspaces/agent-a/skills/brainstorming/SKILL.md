---
name: brainstorming
description: "收到新功能/改版/实现类需求时 MUST 先加载本 skill。通过多轮澄清、方案对比与设计确认，产出 pipeline/jobs/<job-id>/spec.md，用户批准后再入队（status=pending）。"
---

# Brainstorming — 需求分析与规格产出

将用户意图转化为可被下游 Agent（design → coder → verifier）无歧义执行的 `spec.md`。

<HARD-GATE>
在用户明确批准设计之前：
- 不得将 `status.json` 设为 `pending`
- 不得修改 `src/`、不得调用 Stitch / Claude Code
- 不得声称「流水线已接手」
</HARD-GATE>

## 产出路径

- 任务目录：`/home/wmx/workspace/test-pipeline/pipeline/jobs/<job-id>/`
- 规格文件：`spec.md`（按 `pipeline/jobs/_template/spec.md` 结构，并填写「方案对比」「设计摘要」）
- 状态文件：`status.json`
  - 头脑风暴进行中：`status: "draft"`
  - 用户批准后：`status: "pending"`

`job-id` 格式：`job-YYYYMMDD-HHMMSS` 或语义化 slug（全小写、连字符）。

## 流程（按顺序）

1. **探索上下文** — 阅读 `pipeline/jobs/` 近期任务、`README.md`、用户附件；判断范围是否需拆分为多个 job
2. **创建 draft 任务** — 建目录、`status.json`（`draft`）、空壳 `spec.md`（可只写标题与用户原始输入）
3. **澄清问题** — 飞书一次只问一个问题；优先选择题；聚焦目的、约束、验收标准
4. **方案对比** — 给出 2–3 种方案、权衡与推荐（写在飞书摘要中，最终写入 spec）
5. **呈现设计** — 按复杂度分节（架构、组件、数据流、错误处理、测试）；每节后询问是否 OK
6. **写入 spec.md** — 填完整模板各节，含方案对比与设计摘要
7. **自检** — 扫描 TBD/矛盾/歧义/范围过大，当场修正
8. **用户审阅** — 飞书发送 spec 摘要 + job-id，请用户确认或修改
9. **入队** — 用户批准后：`status` → `pending`，`updatedAt` 更新，通知用户流水线将自动接手

**终点是 `status=pending`，不是实现。** 实现由 agent-design / agent-coder / agent-verifier 负责。

## 澄清原则

- 一次一问，不要连发多个问题
- 范围过大时先拆子项目，只对第一个子项目走完整流程
- YAGNI：砍掉非必要功能
- 简单需求设计可很短，但仍须走确认闸门

## 视觉辅助（可选）

若涉及 UI/布局/架构图，可询问用户是否使用 **diagram-maker** 或 **canvas** skill 展示对比图。用户拒绝则用文字继续。

## spec.md 必填节

| 节 | 内容 |
|----|------|
| 目标 | 用户要达成什么 |
| 验收标准 | 可勾选列表，可测试 |
| 背景知识 | 约束、现有系统、依赖 |
| 用户原始输入 | 摘要或转写 |
| 方案对比 | 2–3 方案 + 推荐及理由 |
| 设计摘要 | 架构、关键组件、数据流、错误处理、测试要点 |
| 工作流拆解 | 设计 → 实现 → 验证（模板默认四步） |
| 附件 | `attachments/` 路径 |

## 自检清单

1. 有无 TBD、空节、模糊验收标准？
2. 各节是否自相矛盾？
3. 范围是否适合单次流水线（否则拆分）？
4. 需求是否存在两种合理解读？若有，选定一种写死。

## 用户批准后话术（示例）

> 任务 `{job-id}` 已确认，规格已锁定。流水线将依次执行：Stitch 设计 → Claude Code 实现 → 验证。您可随时回复 job-id 查询进度。

## 续聊与修改

- 用户对 **draft** 任务回复修改意见：更新 `spec.md`，保持 `draft`，再次请求确认
- 用户说「可以了」「确认」「开始吧」等明确批准：才设 `pending`
- 已 `pending` 的任务：不要擅自改 spec；若用户坚持变更，建议新建 job 或等当前任务结束
