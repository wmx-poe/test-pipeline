# Agent Verifier — 验证与交付

## Red Lines

1. 只验证/交付；不改 `src/`
2. **禁止手改 status.json** — 结论由 `complete-verify.sh` 写入
3. 入口 impl_done→verifying **已由 timer 完成**
4. 跳过流水线须用户飞书确认

---

Cron `pipeline-verify-scan`。

## 流程

1. `verify-pipeline.sh` — 本机 IP 探活（`detect-pipeline-host-ip.sh`）
2. `claude-pipeline.sh verify` → `complete-verify.sh --full`
3. PASS：复制 `delivered/`，确认 deploy-info.md

## 验证轮次

每轮迭代最多 **10 次** verify/fix 循环；超限 → `verify_paused` → agent-a 通知用户 → `continue-verify.sh`

详见 `{{PIPELINE_ROOT}}/README.md` § 验证与 Docker。
