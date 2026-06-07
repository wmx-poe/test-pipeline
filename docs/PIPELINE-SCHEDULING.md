# 流水线调度（Timer + 状态机）

OpenClaw Agent **不得**自行触发下游或手改入口状态。调度统一走：

```
pipeline-cron-dispatch.timer（每分钟）
  → scripts/cron-dispatch.sh
    → status 完整性校验（lib/status-integrity.sh）
    → 入口推进（job-transition.sh，PIPELINE_DISPATCH=1）
    → openclaw cron run pipeline-*-scan（仅当存在可信任务）
      → 对应 Agent cron 会话
        → 出口推进（job-transition.sh / complete-verify.sh 等白名单脚本）
```

## 入口 vs 出口状态

| 迁移 | 谁写入 | 脚本 |
|------|--------|------|
| `pending` → `designing` | **仅 timer** | `cron-dispatch.sh` → `job-transition.sh` |
| `designing` → `design_done` | agent-design | `job-transition.sh` |
| `design_done` / `fix_needed` → `implementing` | **仅 timer** | `cron-dispatch.sh` → `job-transition.sh` |
| `implementing` → `impl_done` | agent-coder | `job-transition.sh` |
| `impl_done` → `verifying` | **仅 timer** | `cron-dispatch.sh` → `job-transition.sh` |
| `verifying` → `verified` / `fix_needed` | agent-verifier 链 | `complete-verify.sh` |
| `draft` → `pending` | agent-a（用户批准） | `promote-job.sh` |
| → `fix_needed`（Bug） | agent-a / agent-om | `report-bug.sh` |

**禁止** Agent 用 `write`/`edit` 直接改 `status.json`。

## 防手改 status

`cron-dispatch.sh` 只信任通过 `status_integrity_ok` 的任务：

1. 若存在 `history`：末条 `to` 必须等于当前 `status`
2. 各状态须满足产物门禁（如 `design_done` 须有 `design/DESIGN.md`）
3. 有 `history` 时，`by` 须在白名单（如 `implementing` 仅接受 `job-transition.sh` / `cron-dispatch.sh`）

手改 `status` 字段但无合法 `history`/产物 → **dispatch 忽略**，不会误触发 Agent。

## 常见误解

| 误解 | 事实 |
|------|------|
| 缺 `pipeline-*-scan.sh` 文件 | 那是 OpenClaw cron **任务名**，不是仓库 shell |
| `crontab -l` 无 pipeline | 用 systemd `pipeline-cron-dispatch.timer` |
| Agent 应手推 `fix_needed→implementing` | dispatch 自动 `job-transition` 后触发 coder |
| 可 `openclaw cron run` 自救 | **禁止**；非用户指令不得越界 |

## 运维命令

```bash
VERBOSE=1 ./scripts/cron-dispatch.sh      # 查看跳过原因
DRY_RUN=1 ./scripts/cron-dispatch.sh      # 不触发、不推进
systemctl --user status pipeline-cron-dispatch.timer
```
