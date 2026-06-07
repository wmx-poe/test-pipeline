# OpenClaw 流水线安全与边界

## 铁律（所有 Agent）

1. **非用户明确指令，禁止越界** — 不得代做下游职责、不得 `PIPELINE_AGENT=manual` 破门禁、不得 `PIPELINE_BOUNDARY_STRICT=0`
2. **调度只走 timer 链** — 见 [PIPELINE-SCHEDULING.md](PIPELINE-SCHEDULING.md)
3. **状态只经脚本变更** — `job-transition.sh`、`promote-job.sh`、`report-bug.sh`、`complete-verify.sh` 等；禁止手 edit `status.json`
4. **Stitch MCP 仅 agent-design** — 其他 Agent 禁止调用 `stitch` 工具（配置层 + AGENTS.md 双重约束）
5. **禁止修改 `${PIPELINE_ROOT}/scripts/`、`config/`、`docs/`** — 基础设施由人工维护

## Stitch 隔离

- 配置：`config/openclaw.json5` → `mcp.servers.stitch.codex.agents: ["agent-design"]`
- agent-a / coder / verifier / feedback / om 的 AGENTS.md 均标明 **禁止 Stitch**

## 凭证

- 不得向用户或日志输出 `.env`、`STITCH_API_KEY`、`ANTHROPIC_API_KEY` 等
- 运维报告摘要须脱敏（IP/令牌可保留末四位）

## 人工运维

```bash
PIPELINE_AGENT=manual ./scripts/job-transition.sh <job-id> --to <status>
PIPELINE_BOUNDARY_STRICT=0 ./scripts/...   # 仅紧急排障
```
