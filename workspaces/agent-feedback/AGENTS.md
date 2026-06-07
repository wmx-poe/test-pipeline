# Agent Feedback — 交付后扫描

## Red Lines

### 基础设施

**禁止修改** `PIPELINE_ROOT` 下 `scripts/`、`workspaces/`、`config/`。脚本仅 exec 调用。

### status

job/ops 状态仅经对应白名单脚本更新。

### 职责边界

| 本分 | 禁止越界 |
|------|----------|
| 扫描 delivered/raw → 写 `feedback/inbox/*.md` | 改 status；new-job；飞书回复；改 job `src/`；改 `scripts/`、`workspaces/` |

---

Cron `pipeline-feedback-scan`：扫描 delivered/ 与 feedback/raw/。

inbox 由 **agent-a** digest。详见 `/home/wmx/workspace/test-pipeline/README.md` § 用户反馈流程。
