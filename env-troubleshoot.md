# 环境与服务排查

本文说明：**修改 `config/.env` 后需要重启什么**，以及 **如何确认 OpenClaw 已连通大模型**。适用于本仓库的 OpenClaw + 飞书流水线部署。

相关文档：[README.md](README.md)、[env-troubleshoot.md](env-troubleshoot.md)。

---

## 一、修改 `.env` 后需要重启哪些服务？

### 1.1 结论（一句话）

改完 `config/.env` 后，执行：

```bash
cd /home/wmx/workspace/test-pipeline   # 或你的 PIPELINE_ROOT
./scripts/deploy.sh
openclaw gateway restart
```

本项目**只需重启 OpenClaw Gateway**；Cron、飞书通道、流水线 Agent 都跑在 Gateway 进程内，**没有**单独的 pipeline systemd 服务。

若使用 systemd 用户服务，等价命令：

```bash
systemctl --user restart openclaw-gateway.service
```

### 1.2 为什么必须先 `deploy.sh`？

[`scripts/deploy.sh`](scripts/deploy.sh) 会 `source config/.env`，并把变量写入运行态配置，例如：

| 变量 | 写入位置 |
|------|----------|
| `FEISHU_APP_ID` / `FEISHU_APP_SECRET` | `~/.openclaw/openclaw.json` |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_API_KEY` | `~/.openclaw/openclaw.json`（含 `models.providers.deepseek`） |
| `OPENCLAW_DEFAULT_MODEL` | `~/.openclaw/openclaw.json` |
| `STITCH_API_KEY` | `~/.openclaw/openclaw.json` + Stitch MCP |
| `PIPELINE_ROOT` | 工作区路径、`openclaw.json`、Codex profile |
| `CLAUDE_CODE_*` | `~/.claude/pipeline-settings.json`（Claude Code，与 OpenClaw 独立） |

**只改 `.env` 不跑 `deploy.sh`、也不重启 Gateway**，正在运行的进程不会加载新配置。

部分 Key 若还通过 `openclaw onboard` 写入鉴权存储，改 LLM Key 后可能还需：

```bash
openclaw onboard   # 按向导更新模型提供商
```

### 1.3 按变量类型对照

| 变更内容 | 需要 `deploy.sh` | 需要重启 Gateway |
|----------|:----------------:|:----------------:|
| `FEISHU_APP_ID` / `FEISHU_APP_SECRET` | 是 | 是 |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_API_KEY` | 是 | 是 |
| `OPENCLAW_DEFAULT_MODEL` | 是 | 是 |
| `STITCH_API_KEY` | 是 | 是 |
| `PIPELINE_ROOT` | 是 | 是 |
| `CLAUDE_CODE_API_KEY` / `CLAUDE_CODE_BASE_URL` / `CLAUDE_CODE_DEFAULT_MODEL` | 是 | 否（Claude Code 由 Agent `exec` 调用，非 Gateway） |
| `OPENCLAW_GATEWAY_TOKEN` | 视情况 | 是 |
| 仅本机 Codex CLI 用的 Key（可选） | 不一定 | 否 |

### 1.4 不需要单独重启的组件

| 组件 | 说明 |
|------|------|
| **OpenClaw Cron 定义**（`pipeline-design-scan` 等） | 注册在 `~/.openclaw/cron/jobs.json`，**默认 disabled**；由 `cron-dispatch.sh` 按任务状态 `openclaw cron run` |
| **`pipeline-cron-dispatch.timer`** | 用户 systemd，每分钟跑 dispatch；`setup-cron.sh --install-timer` 安装 |
| **`setup-cron.sh` / `new-job.sh` 等脚本** | 每次执行时读取 `.env`，无常驻进程 |
| **pipeline/jobs 指针 + WORKSPACE_ROOT 工作区** | 磁盘状态，不缓存 `.env` |

仅当**新增或修改 Cron 任务定义**时，才需再执行 `./scripts/setup-cron.sh`（一般不是改 `.env` 的常规步骤）。

### 1.4.1 流水线 Cron dispatch（有任务才扫）

OpenClaw 内 5 条 Cron **保持 `enabled: false`**，避免每分钟空跑 LLM。  
[`scripts/cron-dispatch.sh`](scripts/cron-dispatch.sh) 读 `pipeline/jobs/*/job.md` 索引的工作区 `status.json`，满足条件才 `openclaw cron run`：

| 条件 | 触发的 job |
|------|------------|
| 存在 `pending` 且无 `designing` | `pipeline-design-scan` |
| 存在 `design_done` 或 `fix_needed` 且无 `implementing` | `pipeline-coder-scan` |
| 存在 `impl_done` 且无 `verifying` | `pipeline-verify-scan` |
| `WORKSPACE_ROOT/*/delivered/` 或 `*/feedback/raw/` 有内容 | `pipeline-feedback-scan` |
| `WORKSPACE_ROOT/*/feedback/inbox/*.md` 存在 | `pipeline-a-feedback-digest` |

```bash
./scripts/setup-cron.sh --install-timer   # 安装 systemd timer（每分钟）
VERBOSE=1 DRY_RUN=1 ./scripts/cron-dispatch.sh   # 试跑，只看会触发谁
systemctl --user status pipeline-cron-dispatch.timer
```

改 `.env` 后 dispatch timer **无需**重启；改 `openclaw.json5` 的 `cron.maxConcurrentRuns` 需 `deploy.sh` + `gateway restart`。

### 1.5 systemd 与 `EnvironmentFile`

示例见 [`config/systemd/openclaw-gateway.service.example`](config/systemd/openclaw-gateway.service.example)。`openclaw gateway install` 生成的 unit **不一定**包含 `EnvironmentFile=config/.env`。

本仓库主要依赖 `deploy.sh` 把密钥写入 `~/.openclaw/openclaw.json`。改 `.env` 后仍建议：**`deploy.sh` → `gateway restart`**。

### 1.6 推荐操作顺序

```bash
nano config/.env
./scripts/deploy.sh
openclaw gateway restart
openclaw gateway status
```

### 1.7 Docker（verify-pipeline 必需）

| 现象 | 处理 |
|------|------|
| `verify-pipeline.sh` 报 Docker 不可用 | `./scripts/install-docker.sh`，然后 `newgrp docker` 或重新登录 |
| `permission denied` | `groups` 应含 `docker`；`sudo usermod -aG docker $USER` 后重新登录 |
| `docker compose` 不存在 | `sudo apt install docker-compose-v2` |

详见 [README.md § 验证与 Docker](README.md#验证与-docker)。

---

## 二、如何确认 OpenClaw 已连接大模型？

### 2.1 三层含义（不要混用）

| 层级 | 检查方式 | 能说明什么 |
|------|----------|------------|
| Gateway 在线 | `openclaw gateway status` | 本机 WebSocket 服务正常 |
| 模型配置就绪 | `openclaw models status` | 默认模型、API Key 来源正确 |
| **模型 API 真能调通** | `openclaw infer model run` | **最可靠** |

`gateway status` 里的 **Connectivity probe: ok** 只表示 Gateway 可达，**不能**单独证明大模型已连通。

### 2.2 本项目的模型配置

默认使用 **DeepSeek**（Anthropic 兼容端点），变量在 `config/.env`：

- `ANTHROPIC_BASE_URL` → `https://api.deepseek.com/anthropic`（不带 `/v1`）
- `ANTHROPIC_API_KEY` → DeepSeek API Key
- `OPENCLAW_DEFAULT_MODEL` → 如 `deepseek/deepseek-v4-pro[1m]`

模板见 [`config/openclaw.json5`](config/openclaw.json5) 中 `models.providers.deepseek`。

**Rayin 备用**（OpenAI 兼容）：`config/.env` 与 `openclaw.json5` 中保留了注释块；切换时注释 DeepSeek、取消 Rayin 注释，并改 `OPENCLAW_DEFAULT_MODEL` 为 `rayin/gpt-5.3-codex`。

### 2.3 步骤 1：查看模型与鉴权配置

```bash
source config/.env
./scripts/deploy.sh          # 若刚改过 .env
openclaw models status
```

关注：

- **Default**：应为 `deepseek/deepseek-v4-pro[1m]`（或与 `.env` 一致）
- **Auth overview**：`deepseek` / `anthropic` 等 provider 的 `effective=...` 非空

### 2.4 步骤 2：直接打模型 API（推荐）

```bash
source config/.env

openclaw infer model run \
  --model deepseek/deepseek-v4-pro[1m] \
  --prompt "只回复一个字：好"
```

- **成功**：末尾有模型文本（如「好」）→ Key、`baseUrl`、模型名均通
- **失败**：见 [2.8 常见错误](#28-常见错误)

也可用 `curl` 绕过 OpenClaw，单独验证网络与 Key：

```bash
source config/.env

curl -sS "${ANTHROPIC_BASE_URL%/}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"deepseek-v4-pro[1m]","max_tokens":10,"messages":[{"role":"user","content":"只回复一个字：好"}]}'
```

### 2.5 步骤 3：走完整 Agent 链路

这里的 **Agent** 不是泛指的「AI」，而是 OpenClaw 里配置的**具名智能体**：独立工作区、`AGENTS.md`、可用工具集合和默认模型。本仓库在 [`config/openclaw.json5`](config/openclaw.json5) 中定义了 5 个：

| Agent ID | 职责 |
|----------|------|
| `agent-a` | 飞书对话、写需求 `spec.md`（默认 Agent） |
| `agent-design` | Stitch 设计 |
| `agent-coder` | Claude Code 实现 |
| `agent-verifier` | Claude Code 验证 |
| `agent-feedback` | 反馈扫描 |

「完整 Agent 链路」= 经 **Gateway** 跑一轮真实 Agent（含工作区与工具策略），比 `infer model run` 更接近飞书/Cron 实际路径：

```bash
openclaw agent --agent agent-a --message "回复 OK" --json
```

有正常回复 → Agent + 模型 OK。若日志里出现 **`EMBEDDED FALLBACK`**，说明 Gateway 连接失败、走了本地 embedded 模式——**有回复不等于 Gateway 链路正常**，需按 [§2.8.1](#281-device-token-scope-mismatch) 处理。

### 2.6 步骤 4：日志与状态

```bash
openclaw status              # Sessions 中 Model 应为 deepseek-v4-pro[1m] 等
openclaw logs --follow       # 发飞书或跑 agent 时看 401/429/Connection error
openclaw doctor              # 配置、Gateway、通道体检
openclaw health              # Gateway 与 Agent 摘要
```

### 2.7 步骤 5：飞书端到端（可选）

配对通过后私聊机器人发「你好」：

- **有 AI 回复** → 飞书 + Gateway + LLM 均通
- **Gateway 正常但不回复** → 多用 `infer model run` 或 `models status` 查 LLM

### 2.8 常见错误

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `401` / `invalid api key` | Key 错误或未完成 deploy | 改 `.env` → `deploy.sh` → `gateway restart` |
| `404` / model not found | `OPENCLAW_DEFAULT_MODEL` 与 DeepSeek 侧模型 id 不一致 | 核对 `deepseek-v4-pro[1m]` 等 id |
| `Connection error` | 网络/DNS/代理/站点不可达 | 先 `curl` 测 `/v1/messages`；检查 `HTTP_PROXY`、VPN |
| `models status` 有 Key 但 infer 失败 | Gateway 未加载新配置 | `gateway restart` |
| `device token scope mismatch` / `EMBEDDED FALLBACK` | CLI 设备权限不足（常见：只有 `operator.read`，缺 `operator.write`） | 见 [§2.8.1](#281-device-token-scope-mismatch) |
| `[bundle-mcp] failed to start server "stitch"` | `STITCH_API_KEY` 未填或无效 | 见 [§2.8.2](#282-stitch-mcp-启动失败)；**不影响 agent-a** |
| 配对后仍不回复 | 无有效 LLM Key | 完成 [README.md § 部署指南](README.md#部署指南) + `onboard` |

#### 2.8.1 device token scope mismatch

**典型日志**：

```text
gateway connect failed: ... device token scope mismatch (re-pair or approve scope upgrade)
EMBEDDED FALLBACK: Gateway agent failed; running embedded agent
```

**原因**：本机 CLI 设备最初可能只被批准 `operator.read`（例如 `openclaw doctor` 只读探测），而 `openclaw agent` 经 Gateway 运行需要 `operator.write`。OpenClaw 2026.x 默认启用设备 token 鉴权，权限不足时会拒绝 WebSocket 连接。

**修复**（推荐）：

```bash
# 1. 若尚无 gateway token，生成并重启
openclaw doctor --generate-gateway-token --non-interactive --yes
openclaw gateway restart

# 2. 读取 token（或从 ~/.openclaw/openclaw.json 的 gateway.auth.token 复制）
export OPENCLAW_GATEWAY_TOKEN="$(python3 -c "import json;print(json.load(open('$HOME/.openclaw/openclaw.json'))['gateway']['auth']['token'])")"

# 3. 查看待批准的 scope 升级
openclaw devices list --token "$OPENCLAW_GATEWAY_TOKEN"

# 4. 批准（可能需要执行 1～2 次，直到 Paired Scopes 含 operator.write）
openclaw devices approve --latest --token "$OPENCLAW_GATEWAY_TOKEN"
# 或指定 requestId：openclaw devices approve <requestId> --token "$OPENCLAW_GATEWAY_TOKEN"

# 5. 确认 Paired Scopes 含 operator.read、operator.write 后重测
openclaw agent --agent agent-a --message "回复 OK" --json
```

也可打开 Control UI **http://127.0.0.1:18789/** 在界面批准 scope upgrade。

**临时绕过**（仅测模型，不验证 Gateway 全链路）：

```bash
openclaw infer model run --model deepseek/deepseek-v4-pro[1m] --prompt "好"
openclaw agent --agent agent-a --message "回复 OK" --local --json
```

#### 2.8.2 Stitch MCP 启动失败

**典型日志**：

```text
[bundle-mcp] failed to start server "stitch" ... Connection closed
```

**原因**：`STITCH_API_KEY` 未配置、已过期或无效。仅 **agent-design** 依赖 Stitch；**agent-a 飞书对话不受影响**。

**修复（推荐：API Key，无需 gcloud）**：

1. 打开 https://stitch.withgoogle.com → **Stitch settings** → **Create key**
2. 写入 `config/.env`：

```bash
export STITCH_API_KEY="你的-key"
./scripts/deploy.sh
openclaw gateway restart
```

3. 验证：`openclaw mcp show stitch` 应显示 `url: https://stitch.googleapis.com/mcp`

详见 [README.md § 部署指南](README.md#部署指南)（Stitch MCP）。

### 2.9 推荐自检顺序

```text
models status  →  infer model run  →  openclaw agent（可选）  →  飞书私聊（可选）
```

### 2.10 命令速查

| 目的 | 命令 |
|------|------|
| Gateway 是否运行 | `openclaw gateway status` |
| 模型与 Key 配置 | `openclaw models status` |
| **验证 Claude Code 连通** | `claude --bare -p "好" --settings ~/.claude/pipeline-settings.json` |
| 验证 Agent 全链路 | `openclaw agent --agent agent-a -m "OK"` |
| 设备权限 / scope 升级 | `openclaw devices list --token "$OPENCLAW_GATEWAY_TOKEN"` |
| 批准 scope 升级 | `openclaw devices approve --latest --token "$OPENCLAW_GATEWAY_TOKEN"` |
| 实时日志 | `openclaw logs --follow` |

---

## 三、`.env` 变更 + 模型验证（合并流程）

改密钥或代理地址时，可一次性执行：

```bash
cd /home/wmx/workspace/test-pipeline
nano config/.env
./scripts/deploy.sh
openclaw gateway restart
openclaw gateway status
openclaw models status
openclaw infer model run --model deepseek-v4-pro[1m] --prompt "只回复一个字：好"
claude --bare -p "只回复一个字：好" --settings ~/.claude/pipeline-settings.json
```

全部通过后再测飞书或 Cron。

---

## 四、相关文件

| 文件 | 说明 |
|------|------|
| [`config/.env`](config/.env) | 本地密钥（勿提交 Git） |
| [`config/env.example`](config/env.example) | 变量模板 |
| [`config/openclaw.json5`](config/openclaw.json5) | 部署前模板 |
| [`~/.openclaw/openclaw.json`](file:///home/wmx/.openclaw/openclaw.json) | 部署后的运行配置 |
| [`scripts/deploy.sh`](scripts/deploy.sh) | `.env` → OpenClaw 配置 |
