# Agent 职责边界

流水线按 **Agent 分工** 运行：每个 OpenClaw Agent 只处理自己阶段的工作，**禁止越界**代做下游活。

## 全局铁律（OpenClaw 必读）

1. **非用户明确指令，禁止越界** — 不因「卡住/无人处理」自行代跑下游、手改 status、或 `openclaw cron run`
2. **Timer + 状态机唯一路径** — `pipeline-cron-dispatch.timer` → `cron-dispatch.sh` → `pipeline-*-scan`；详见 [PIPELINE-SCHEDULING.md](PIPELINE-SCHEDULING.md)
3. **状态变更只经脚本** — 入口状态（`pending→designing` 等）**仅 timer** 经 `job-transition.sh`；出口由各 Agent 经白名单脚本；**禁止**手 edit `status.json`
4. **Stitch 仅 agent-design** — 其他 Agent 禁止调用 Stitch MCP（见 `config/openclaw.json5`）
5. **dispatch 不信任手改 status** — `lib/status-integrity.sh` 校验 history + 产物后门禁

## 分工一览

| Agent | 职责 | 可写目录/产物 | 禁止 |
|-------|------|---------------|------|
| **agent-a** | 飞书对话、需求/反馈/运维**下发** | `spec.md`、`ops/inbox/`（经 `agent-a-run.sh`） | docker/systemctl、改 `src/`、Stitch、验证 |
| **agent-design** | Stitch UI 设计 | `design/`；`job-transition.sh`（→design_done） | 改 `src/`、`spec.md`（除门禁失败说明）、验证、手改 status |
| **agent-coder** | 实现与修复 | `src/`、`implement-summary.md`；`job-transition.sh`（→impl_done） | 改 `design/`、标 `verified`、Stitch、手改 status |
| **agent-verifier** | 运行时验证与交付 | `reports/verify*.md`、`deploy-info.md`、`delivered/` | 改 `src/`、Stitch、手改 status |
| **agent-feedback** | 扫描交付与 raw 反馈 | `feedback/inbox/*.md` | 改 `spec`/`src`/`status`、Stitch、调 `reopen-job` |
| **agent-om** | 项目运维（部署/日志/诊断） | `<project>/ops/reports/*.md` | 改 `src/`、Stitch、飞书回复、手推入口 status |

## 硬隔离（配置层）

1. **飞书** → 仅 `agent-a`（`config/openclaw.json5` `bindings`）
2. **Stitch MCP** → 仅 `agent-design`（`mcp.servers.stitch.codex.agents`）
3. **Cron dispatch** → 按 `status.json` 只触发对应 Agent
4. **Claude Code** → `implement` 可写、`verify` 只读（`claude-pipeline.sh`）

## 脚本门禁（执行层）

`PIPELINE_BOUNDARY_STRICT=1`（默认）时，关键脚本会校验调用方：

| 脚本 | 允许调用方 |
|------|------------|
| `new-job.sh` | agent-a, manual |
| `promote-job.sh` | agent-a, manual |
| `validate-spec.sh` | agent-a, agent-design, manual |
| `report-bug.sh` | agent-a, agent-om, manual |
| `report-feedback.sh` | agent-a, manual |
| `reopen-job.sh` | agent-a, manual（委托 report-bug） |
| `continue-verify.sh` | agent-a, manual |
| `agent-a-run.sh` | agent-a, manual |
| `deploy-servers-list.sh` | agent-a, agent-om, manual |
| `om-task-create.sh` / `om-task-list.sh` / `om-task-cancel.sh` | agent-a, manual |
| `om-task-claim.sh` / `om-task-complete.sh` | agent-om, manual |
| `claude-pipeline.sh implement\|resume\|verify-fix` | agent-coder, manual |
| `claude-pipeline.sh verify` | agent-verifier, manual |
| `verify-pipeline.sh` | agent-verifier, manual |
| `complete-verify.sh` | agent-verifier, verify-chain, manual |
| `job-transition.sh` | agent-design, agent-coder, agent-a（verify_paused→verify_failed）, cron-dispatch（`PIPELINE_DISPATCH=1`）, manual |

`verify-chain`：由 `verify-pipeline.sh` / `claude-pipeline.sh verify` 内部设置 `PIPELINE_VERIFY_CHAIN=1` 时允许。

**入口状态**（`pending→designing`、`design_done|fix_needed→implementing`、`impl_done→verifying`）**仅** `cron-dispatch.sh` 在 `PIPELINE_DISPATCH=1` 时调用 `job-transition.sh`。

### 调用方识别

1. 环境变量 `PIPELINE_AGENT=<agent-id>`（**Agent 执行 exec 时必须设置**）
2. `OPENCLAW_AGENT_ID`（若 Gateway 注入）
3. 父进程命令行推断（`agent:agent-coder:cron`、`--agent agent-a`）

### 人工运维

```bash
# 显式声明人工调用（绕过边界）
PIPELINE_AGENT=manual ./scripts/promote-job.sh job-xxx

# 临时关闭门禁
PIPELINE_BOUNDARY_STRICT=0 ./scripts/claude-pipeline.sh verify .../src "..."
```

在 `config/.env` 中可设置：

```bash
export PIPELINE_BOUNDARY_STRICT=1   # 0=关闭脚本门禁
```

## Agent 执行脚本规范

各 Agent 通过 `exec` 调用脚本时 **必须** 带 `PIPELINE_AGENT`：

```bash
PIPELINE_AGENT=agent-a {{PIPELINE_ROOT}}/scripts/reopen-job.sh job-xxx --reason "..." --by feishu-user
PIPELINE_AGENT=agent-design {{PIPELINE_ROOT}}/scripts/validate-spec.sh job-xxx
PIPELINE_AGENT=agent-design {{PIPELINE_ROOT}}/scripts/job-transition.sh job-xxx --to design_done
PIPELINE_AGENT=agent-coder {{PIPELINE_ROOT}}/scripts/claude-pipeline.sh implement .../src "..."
PIPELINE_AGENT=agent-coder {{PIPELINE_ROOT}}/scripts/job-transition.sh job-xxx --to impl_done
PIPELINE_AGENT=agent-verifier {{PIPELINE_ROOT}}/scripts/claude-pipeline.sh verify .../src "..."
```

## 状态机与越界

```
draft ──agent-a/promote-job──► pending
pending ──timer/job-transition──► designing ──agent-design──► design_done
design_done ──timer/job-transition──► implementing ──agent-coder──► impl_done
fix_needed ──timer/job-transition──► implementing ──agent-coder──► impl_done（回流）
impl_done ──timer/job-transition──► verifying ──agent-verifier/complete-verify──► verified | fix_needed
```

入口迁移（`pending→designing` 等）**仅** `cron-dispatch.sh` + `PIPELINE_DISPATCH=1`。详见 [PIPELINE-SCHEDULING.md](PIPELINE-SCHEDULING.md)。

## 需求 / 运维 / Bug 融合

| 意图 | agent-a | agent-om | agent-coder |
|------|---------|----------|-------------|
| **新需求** | spec、`new-job`/`promote` | — | 实现（design_done 后） |
| **运维** | `om-task-create` 指挥 | 执行 ops 任务 | — |
| **Bug** | `report-bug.sh` → `bugs.md` | `report-bug.sh` → `bugs.md`（**同等进 coder**） | 读 `bugs.md` + `verify-feedback.md` + 必要时 `ops/reports/` |
| **用户反馈** | `report-feedback.sh` → `user-feedback.md` | — | **不**自动读取 |

详见 [BUG-FLOW.md](BUG-FLOW.md)。

缺陷 / 验证失败：**`fix_needed`** → coder 读 **`bugs.md`** + **`verify-feedback.md`**。用户意见在 **`user-feedback.md`**，由 agent-a 分拣，不自动进 coder。
