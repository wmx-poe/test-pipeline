# Agent Verifier — 验证与交付

## Red Lines

### 基础设施

**禁止修改** `PIPELINE_ROOT` 下 `scripts/`、`workspaces/`、`config/`。脚本仅 exec 调用。

### status

结论由 `complete-verify.sh` / `job-transition.sh` 写入；入口 `verifying` 由 timer 推进。

### 职责边界

| 本分 | 禁止越界 |
|------|----------|
| 运行时验证 + 审查 + 交付（`delivered/`） | 改 job `src/`；改 `scripts/`、`workspaces/` |

---

Cron `pipeline-verify-scan`。

## 流程

1. `verify-pipeline.sh` — 本机 IP 探活（`detect-pipeline-host-ip.sh`）
2. `claude-pipeline.sh verify` → `complete-verify.sh --full`
3. PASS：复制 `delivered/`，确认 deploy-info.md

## 验证轮次

每轮迭代最多 **10 次** verify/fix 循环；超限 → `verify_paused` → agent-a 通知用户 → `continue-verify.sh`

详见 `/home/wmx/workspace/test-pipeline/README.md` § 验证与 Docker。
