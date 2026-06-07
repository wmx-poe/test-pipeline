# 验证与部署约定

本流水线 **禁止仅做静态代码审查**。验证须 Docker 部署 + 探活 + 失败回流。

## 验证轮次（每轮迭代 10 次）

一次**迭代**内，验证不通过时自动 fix→re-verify，最多 **10 轮**（`maxVerifyRounds: 10`）。

| 轮次 | 行为 |
|------|------|
| 1–10 FAIL | `fix_needed` → coder 修复 → 再验证 |
| 第 10 次仍 FAIL | `verify_paused` → agent-a 飞书问用户 |
| 用户「继续验证」 | `continue-verify.sh` → 新一轮（verifyRound 归零，verifyIteration+1） |
| 用户「放弃」 | agent-a 与用户确认后续 |

`status.json` 字段：

```json
{
  "verifyRound": 0,
  "verifyIteration": 0,
  "maxVerifyRounds": 10
}
```

## 本地验证服务器

test-pipeline **部署机 IP** 作为本地验证探活主机：

```bash
{{PIPELINE_ROOT}}/scripts/detect-pipeline-host-ip.sh
```

`verify-pipeline.sh` 自动设置 `VERIFY_DEPLOY_HOST`。生产部署服务器在 `config/.env`（`DEPLOY_SERVER_PROD_*`），由 agent-om 在用户指定 `--server prod` 时使用。

## 验证链

```bash
{{PIPELINE_ROOT}}/scripts/verify-pipeline.sh <job-id>
{{PIPELINE_ROOT}}/scripts/claude-pipeline.sh verify .../src "..."
# 自动 complete-verify.sh --full
```

| 结果 | status |
|------|--------|
| PASS | verified |
| FAIL（轮次内） | fix_needed |
| FAIL（10 次用尽） | verify_paused |

## 状态机

```
impl_done → verifying → (PASS) verified → delivered/
                    ↘ (FAIL, round≤10) fix_needed → implementing → impl_done → ...
                    ↘ (FAIL, round>10) verify_paused → [用户确认] continue-verify → impl_done → ...
```

**status 仅由 timer + 白名单脚本修改**，Agent 禁止手改。见 `docs/PIPELINE-SCHEDULING.md`。

## agent-verifier 职责

1. 运行时验证（必须先执行）
2. Claude Code 综合审查
3. PASS：复制 delivered/，deploy-info.md 含 URL 与测试账号

## agent-coder 修复

fix_needed 时读 verify-feedback.md、bugs.md，修复后 job-transition → impl_done。

## Docker

见原文 § Docker 环境；`install-docker.sh` 为必需依赖。

## 环境变量

| 变量 | 说明 |
|------|------|
| `VERIFY_DEPLOY_HOST` | 探活主机（默认=流水线本机 IP） |
| `PIPELINE_HOST_IP` | 显式指定本机 IP |
| `DEPLOY_SERVER_PROD_*` | 生产部署（env） |
