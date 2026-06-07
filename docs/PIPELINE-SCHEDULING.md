# 流水线调度（Timer / Cron）

## 原则

**所有状态自动流转由 timer 驱动，OpenClaw Agent 不得自行修改 status。**

```
pipeline-cron-dispatch.timer（每分钟）
    → cron-dispatch.sh
        → job-transition.sh（入口 status：pending→designing 等）
        → openclaw cron run pipeline-*-scan（有任务才触发）
```

OpenClaw 内 7 条 Cron **保持 `enabled: false`**，避免空跑 LLM。

## Cron 任务列表

| Cron 名 | Agent | 触发条件 |
|---------|-------|----------|
| `pipeline-design-scan` | agent-design | pending / designing 卡死 |
| `pipeline-coder-scan` | agent-coder | design_done / fix_needed / implementing 卡死 |
| `pipeline-verify-scan` | agent-verifier | impl_done / verifying 卡死 / verified 未交付 |
| `pipeline-om-scan` | agent-om | ops/tasks 有 pending |
| `pipeline-feedback-scan` | agent-feedback | delivered 或 raw 有内容 |
| `pipeline-a-feedback-digest` | agent-a | inbox 有未处理 md |
| `pipeline-a-verify-notify` | agent-a | verify_paused 待通知用户 |

## 入口 status（仅 timer 可写）

| 流转 | 时机 |
|------|------|
| pending → designing | dispatch 触发 design-scan 前 |
| design_done → implementing | dispatch 触发 coder-scan 前 |
| fix_needed → implementing | dispatch 触发 coder-scan 前 |
| impl_done → verifying | dispatch 触发 verify-scan 前 |

Agent 扫描会话内 **status 已是「进行中」**，直接执行业务，**禁止**再手改入口 status。

## 出口 status（经白名单脚本）

| 脚本 | 流转 |
|------|------|
| `promote-job.sh` | draft → pending |
| `job-transition.sh` | designing → design_done |
| `job-transition.sh` | implementing → impl_done |
| `complete-verify.sh` | verifying → verified / fix_needed / verify_paused |
| `continue-verify.sh` | verify_paused → impl_done（用户确认下一轮） |
| `report-bug.sh` | * → fix_needed |

## 给 OpenClaw 的明确指令

1. **不要**自行 `edit`/`write` `status.json`
2. **不要**因「卡住」而跳过 dispatch 直接跑下游
3. 需要破例时 → **飞书问用户** → 用户同意后再操作
4. 状态异常时调用 `job-status.sh` 只读查看；修复依赖 `status-integrity.sh` 容错

## 调试

```bash
VERBOSE=1 ./scripts/cron-dispatch.sh
VERBOSE=1 DRY_RUN=1 ./scripts/cron-dispatch.sh
systemctl --user status pipeline-cron-dispatch.timer
```
