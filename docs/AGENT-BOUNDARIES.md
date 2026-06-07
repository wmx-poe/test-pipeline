# Agent 职责边界

OpenClaw 各 Agent **只负责各自部分，禁止越界**。若需跳过流水线规则，**必须在飞书与用户确认**，并设置 `PIPELINE_USER_OVERRIDE=1`。

## 总览

| Agent | 职责 | 禁止 |
|-------|------|------|
| **agent-a** | 飞书唯一入口；需求设计；查状态；分流 Bug/反馈/运维 | 写 `src/`；手改 status；代跑 verify/implement；自写 shell 改文件 |
| **agent-om** | 部署/日志/诊断等耗时运维；运维 Bug 登记 | 写 `src/`；改 spec/design；飞书对用户回复 |
| **agent-design** | Stitch → `design/` | 改 `src/`；跑 claude-pipeline |
| **agent-coder** | `src/` 实现与修复 | 跑 verify；改 design；标 verified |
| **agent-verifier** | 运行时验证 + 审查 + 交付 | 改 `src/`；implement |
| **agent-feedback** | 扫描 delivered/raw → inbox | 改 status；new-job；飞书回复 |

## 状态修改规则（铁律）

**所有 status 流转仅允许：**

1. **systemd timer** → `cron-dispatch.sh` → `job-transition.sh`（入口状态）
2. **白名单脚本**：`promote-job.sh`、`report-bug.sh`、`complete-verify.sh`、`continue-verify.sh`、`reopen-job.sh`、`job-transition.sh`

**OpenClaw Agent 禁止** `write`/`edit` 直接修改 `status.json`。

## 同一需求 / Bug 不开新 job

| 场景 | 动作 |
|------|------|
| 新功能、新需求 | `new-job.sh` |
| Bug、验证失败、交付后缺陷 | **原 job**：`report-bug.sh` / `reopen-job.sh` |
| 用户反馈（建议） | `report-feedback.sh`（不自动 coder） |

## agent-a 与 agent-om 分工

- **agent-a**：与用户沟通；读各 Agent 的 MD 报告汇总；下发 `om-task-create.sh`
- **agent-om**：执行运维任务；发现代码问题用 `report-bug.sh --om-task <id>`

## 跳过流水线须用户确认

以下行为须用户在飞书**明确同意**后才能执行：

- 手改 `status.json` 推进流水线
- 直接 `openclaw cron run` 跳过 dispatch
- `PIPELINE_AGENT=manual` 或未授权脚本改状态

未确认时 Agent 应说明原因并等待用户指令。
