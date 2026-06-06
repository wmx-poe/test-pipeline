# OpenClaw 流水线部署指南

本指南为流水线部署与凭证的完整说明，对应 [config/env.example](../config/env.example) 与 [README.md](../README.md)。运维排错见 [env-troubleshoot.md](../env-troubleshoot.md)。

## 目录

- [一、快速开始](#一快速开始)
- [二、本机安装 OpenClaw](#二本机安装-openclaw)
- [三、飞书开放平台](#三飞书开放平台)
- [四、长连接、发布与配对](#四长连接发布与配对)
- [五、飞书补充配置](#五飞书补充配置)
- [六、LLM 凭证](#六llm-凭证)
- [七、Google Stitch MCP](#七google-stitch-mcp)
- [八、Claude Code CLI](#八claude-code-cli)
- [九、Codex CLI（可选）](#九codex-cli可选)
- [十、汇总部署](#十汇总部署)
- [十一、验收检查表](#十一验收检查表)
- [十二、常见问题](#十二常见问题)
- [十三、相关文档](#十三相关文档)

```mermaid
flowchart TB
  subgraph phaseA [阶段A 本机]
    A1[Node + openclaw CLI]
    A2[config/.env]
    A3[onboard + deploy]
    A4[安装飞书插件]
    A5[gateway install/start]
  end
  subgraph phaseB [阶段B 飞书开放平台]
    B1[自建应用 + 权限]
    B2[Gateway 在线后保存长连接]
    B3[发布应用]
  end
  subgraph phaseC [阶段C 验证]
    C1[飞书私聊机器人]
    C2[pairing approve]
    C3[收到 AI 回复]
  end
  A1 --> A2 --> A3 --> A4 --> A5 --> B2
  B1 --> B2 --> B3 --> C1 --> C2 --> C3
```

---

## 一、快速开始

| 准备项 | 说明 |
|--------|------|
| Ubuntu 22.04+ | 本项目部署机 |
| 飞书企业账号 | 能创建自建应用 |
| App ID / App Secret | 开放平台 → 凭证与基础信息 |
| LLM API Key | DeepSeek / Anthropic / OpenAI |
| 网络 | 服务器能访问飞书 API（出站 HTTPS/WSS） |

```bash
cd /home/wmx/workspace/test-pipeline
./scripts/install-ubuntu.sh
./scripts/install-docker.sh    # 若 Docker 未装好或 verify 报不可用
newgrp docker                  # 或重新登录，使 docker 组生效
cp -n config/env.example config/.env && nano config/.env
openclaw onboard --install-daemon
./scripts/deploy.sh
./scripts/setup-feishu.sh
# Gateway 在线后 → 飞书开放平台保存长连接并发布
openclaw pairing approve feishu <CODE>
./scripts/setup-cron.sh --install-timer
```

建议按 **二 → 三 → 四 → 六 → 七 → 八** 顺序首次部署。

---

---

## 二、本机安装 OpenClaw

### A1. 安装 Node、OpenClaw、Claude Code（一键脚本）

```bash
cd /home/wmx/workspace/test-pipeline
./scripts/install-ubuntu.sh
```

### A1.1 安装 Docker（验证阶段必需）

验证流水线需要 Docker 做容器化部署与探活。新机或缺失环境：

```bash
cd /home/wmx/workspace/test-pipeline
./scripts/install-docker.sh
newgrp docker    # 或重新登录 SSH，使 docker 组生效
docker info      # 验收
```

完整说明与排错：[VERIFICATION.md § Docker 环境](VERIFICATION.md#docker-环境必需从零安装)。

或已装 Node 时手动：

```bash
export PATH="$HOME/.local/node/bin:$HOME/.local/npm-global/bin:$PATH"
npm install -g openclaw@latest @anthropic-ai/claude-code@latest
```

**加载 PATH（每个新终端都要，或已写入 `~/.bashrc`）：**

```bash
source ~/.bashrc
# 或
source /home/wmx/workspace/test-pipeline/scripts/env.sh

openclaw --version    # 应输出版本号，例如 OpenClaw 2026.5.22
```

若提示 `command not found`，见 [第十二节 Q1](#q1-openclaw-command-not-found)。

---

### A2. 填写 `config/.env`

```bash
cd /home/wmx/workspace/test-pipeline
cp -n config/env.example config/.env
nano config/.env
```

至少填写：

```bash
export PIPELINE_ROOT="/home/wmx/workspace/test-pipeline"
export WORKSPACE_ROOT="/home/wmx/workspace/pipeline-workspace"
export FEISHU_APP_ID="cli_xxxxxxxx"
export FEISHU_APP_SECRET="你的AppSecret"
export ANTHROPIC_API_KEY="sk-ant-..."          # 或 OPENAI_API_KEY
export OPENCLAW_DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
```

`WORKSPACE_ROOT` 是与 `test-pipeline` 平级的任务工作区根目录（默认 `../pipeline-workspace`）。每个任务的代码、设计、报告存放在 `$WORKSPACE_ROOT/<project>/jobs/<job-id>/`；编排仓库内 `pipeline/jobs/<job-id>/job.md` 仅作指针。项目名 `<project>` 由 `new-job.sh` 创建时从 title 自动 slug 化。

---

### A3. 首次初始化 OpenClaw（仅第一次）

```bash
source ~/.bashrc
cd /home/wmx/workspace/test-pipeline
source config/.env

openclaw onboard --install-daemon
```

向导建议：

- Gateway：**本地 (local)**
- 模型：选你已配置的 Anthropic / OpenAI
- 安装 **systemd 用户服务**（后台常驻 Gateway）

---

### A4. 部署本项目配置

```bash
cd /home/wmx/workspace/test-pipeline
./scripts/deploy.sh
```

作用：生成 `~/.openclaw/openclaw.json`，写入飞书 AppId/Secret、多 Agent、Stitch MCP 等。

检查：

```bash
test -f ~/.openclaw/openclaw.json && echo "配置文件 OK"
```

---

### A5. 安装飞书插件（必做，否则飞书不会连）

OpenClaw 2026.x 的飞书通道是**独立插件**，未安装时 `openclaw status` 会显示 `plugin not installed`。

```bash
source ~/.bashrc
openclaw plugins install @openclaw/feishu
```

或一键脚本（含 A4～A6）：

```bash
cd /home/wmx/workspace/test-pipeline
./scripts/setup-feishu.sh
```

---

### A6. 安装并启动 Gateway

```bash
source ~/.bashrc
openclaw gateway install    # 首次：安装 systemd 用户服务 + 生成 gateway token
openclaw gateway start      # 启动（或 restart）
openclaw gateway status     # Runtime: running, Connectivity probe: ok
```

**期望输出要点：**

- `Runtime: running`
- `Listening: 127.0.0.1:18789`
- `Connectivity probe: ok`

实时日志（保存飞书长连接前建议开着）：

```bash
journalctl --user -u openclaw-gateway.service -f
# 或
openclaw logs --follow
```

**期望出现（飞书相关）：**

```text
starting feishu[default] (mode: websocket)
WebSocket client started
```

确认通道状态：

```bash
openclaw status
```

Channels 表格中 **Feishu** 应为 `ON` + `OK`（不是 WARN / plugin not installed）。

---

### 命令速查（复制执行）

```bash
# === 环境 ===
source ~/.bashrc
cd /home/wmx/workspace/test-pipeline
source config/.env

# === 安装（首次）===
./scripts/install-ubuntu.sh
openclaw onboard --install-daemon

# === 飞书通道（每次改 Secret 后）===
./scripts/deploy.sh
openclaw plugins install @openclaw/feishu
openclaw gateway restart

# === 检查 ===
openclaw gateway status
openclaw status
journalctl --user -u openclaw-gateway.service -n 50 --no-pager

# === 配对 ===
openclaw pairing list feishu
openclaw pairing approve feishu <CODE>
```

---

---

## 三、飞书开放平台

**用途**：飞书机器人收发消息（文字、图片、语音、文件）。

### 1.1 注册开放平台应用

1. 打开 [飞书开放平台](https://open.feishu.cn/app)（国际版用 [Lark Developer](https://open.larksuite.com/app)）。
2. 使用**企业管理员或有创建应用权限**的账号登录。
3. 点击 **创建企业自建应用** → 填写名称、描述 → 创建。

### 1.2 获取 App ID 与 App Secret

1. 进入应用 → 左侧 **凭证与基础信息**（或「应用凭证」）。
2. 复制：
  - **App ID**（形如 `cli_xxxxxxxx`）→ `FEISHU_APP_ID`
  - **App Secret** → `FEISHU_APP_SECRET`（仅显示一次时需立即保存；泄露后在同页重置）

### 1.3 开启机器人能力

1. 左侧 **应用能力** → **机器人** → 启用。
2. 设置机器人名称、头像（用户 @ 时显示）。

### 1.4 配置权限（Scope）

在 **权限管理** 中申请并开通（至少）：


| 权限                           | 说明              |
| ---------------------------- | --------------- |
| `im:message`                 | 收发消息            |
| `im:message:send_as_bot`     | 以机器人身份发消息       |
| `im:chat`                    | 获取群信息           |
| `contact:user.base:readonly` | 读取用户基础信息（解析发送者） |


按需增加：文件、图片、获取消息内容等（与你要用的消息类型一致）。

**在开放平台操作：**

1. 左侧 **开发配置** → **权限管理**（有的版本叫「安全设置」旁的「权限」）。
2. 搜索上表中的权限名 → 点击 **申请权限** → 等待管理员在企业管理后台 **通过**（自建应用有时自动通过）。
3. 权限状态变为 **已开通** 后再进行下面的 1.5。

---

## 四、长连接、发布与配对

> Gateway 须先按第二节跑通，再保存长连接。

在 **Gateway 已 running** 且 **Feishu 通道 OK** 后再做「保存长连接」。

### B1. 创建应用（若尚未完成）

1. 打开 https://open.feishu.cn/app
2. **创建企业自建应用** → 记录 **App ID**、**App Secret**
3. **应用能力** → **机器人** → 启用
4. **权限管理** → 申请并开通至少：
   - `im:message`
   - `im:message:send_as_bot`
   - `im:chat`
   - `contact:user.base:readonly`

### B2. 事件订阅 — 长连接（关键）

1. 确认本机：`openclaw gateway status` → **running**
2. 开放平台 → **开发配置** → **事件订阅**
3. 订阅方式选：**使用长连接接收事件**（不要只配 Webhook）
4. 添加事件：`im.message.receive_v1`
5. 点击 **保存**

| 保存结果 | 含义 |
|----------|------|
| 成功 | OpenClaw 已与飞书建立长连接，可进行 B3 |
| 失败「未建立连接」 | 回到 A6：`gateway restart`，看日志是否有 `WebSocket client started`，核对 App Secret |

### B3. 发布应用

1. **版本管理与发布** → 创建版本 → 提交审核 → **发布**
2. 未发布时，员工可能搜不到机器人或无法正常使用

### B4. 在飞书中找到机器人

- 工作台搜索应用名，或
- 消息里搜索机器人名称 → 进入单聊

---

---

默认 `dmPolicy: pairing`，陌生人需先配对。

### C1. 飞书给机器人发消息

发送：`你好`

### C2. 服务器批准配对

```bash
source ~/.bashrc
openclaw pairing list feishu
openclaw pairing approve feishu <配对码>
```

### C3. 再次发消息

若已配置 LLM API Key，Agent A 应回复。若无回复：

```bash
openclaw logs --follow
```

检查 `ANTHROPIC_API_KEY` / `onboard` 是否完成。

### C4. 群聊（可选）

拉机器人进群，发送：`@机器人名 你好`（默认需 @）

---

---

### 4.5 事件订阅（长连接）— 网页端详细步骤

> **含义**：飞书用「长连接」时，是你的服务器上的 OpenClaw **主动连飞书**，不是飞书访问你的 URL。所以必须先有 **第二节** 里跑起来的 Gateway，飞书才允许保存配置。

#### 4.5.1 打开事件订阅页

1. 登录 [飞书开放平台](https://open.feishu.cn/app) → 进入你的应用。
2. 左侧菜单：**开发配置** → **事件订阅**（或 **事件与回调**）。

#### 4.5.2 选择「使用长连接接收事件」

1. 在 **订阅方式** 区域，选择 **使用长连接接收事件**（不要选「将事件发送至开发者服务器」除非你自己做了公网 Webhook）。
2. 此时先**不要点保存**（若页面有保存按钮）。

#### 4.5.3 确认 Gateway 已连接

回到服务器，确认：

```bash
openclaw gateway status
```

`openclaw logs --follow` 窗口无连续报错。然后再进行 4.5.4。

#### 4.5.4 添加事件

1. 在 **订阅事件** 列表中点击 **添加事件**。
2. 搜索并勾选：**接收消息** `im.message.receive_v1`。
3. （可选）若要用群聊：确认第三节里群相关权限已开通。

#### 4.5.5 保存配置

1. 点击页面底部 **保存** 或 **确定**。
2. **成功**：提示保存成功，长连接状态为「已连接」或类似绿色状态。
3. **失败**（常见文案：未建立连接、请先建立长连接）：
  - 回到服务器执行 `openclaw gateway restart`，等 10～30 秒
  - 再看 `openclaw logs --follow` 是否连上
  - 检查 `FEISHU_APP_ID` / `FEISHU_APP_SECRET` 是否与开放平台完全一致（无空格）
  - 再回网页点一次保存

#### 4.5.6 可选：用 CLI 写入飞书凭证

若 `deploy.sh` 未跑或想重新绑定：

```bash
source ~/.bashrc
openclaw channels login --channel feishu
```

- 选 **manual（手动）**，粘贴 App ID、App Secret。
- 完成后：`openclaw gateway restart`。

---

### 4.6 发布应用 — 详细步骤

未发布的应用，员工在飞书里**搜不到机器人**或无法正常使用。

#### 4.6.1 创建版本

1. 开放平台左侧：**应用发布** → **版本管理与发布**（名称可能略有不同）。
2. 点击 **创建版本**。
3. 填写版本号（如 `1.0.0`）、更新说明。
4. 确认本版本包含：机器人能力、已开通的权限、事件订阅（长连接 + `im.message.receive_v1`）。

#### 4.6.2 提交审核并发布

1. 点击 **保存并申请发布** / **提交审核**。
2. 企业自建应用：通常由 **租户管理员** 在 [飞书管理后台](https://www.feishu.cn/admin) → **工作台** → **应用管理** 里审批。
3. 审批通过后，回到开放平台该版本 → 点击 **发布** / **全量发布**。
4. 状态变为 **已发布** 或 **线上**。

#### 4.6.3 把机器人提供给使用者

1. 飞书客户端 → **工作台** → 找到你的应用；或
2. 在 **消息** 里搜索机器人名称 → 进入单聊；或
3. 在群里 **添加机器人**（群设置 → 群机器人 → 添加）。

---

### 4.7 本机配置与「配对」— 详细步骤

OpenClaw 默认 **不允许陌生人** 直接私聊机器人，需要先 **配对（pairing）**。

#### 4.7.1 再次确认 Gateway 在跑

```bash
source ~/.bashrc
openclaw gateway status
openclaw gateway restart   # 若未运行
```

#### 4.7.2 用飞书给机器人发第一条消息

1. 飞书 App 打开与机器人的 **单聊**。
2. 发送任意文字，例如：`你好`。
3. 机器人可能回复一个 **配对码**（或提示需要配对），此时它还不会正常对话。

#### 4.7.3 在服务器批准配对

```bash
source ~/.bashrc
openclaw pairing list feishu
```

输出示例（示意）：

```text
feishu  ABC123  ou_xxxxxxxx  pending
```

记下 **配对码**（如 `ABC123`），执行：

```bash
openclaw pairing approve feishu ABC123
```

将 `ABC123` 换成你列表里看到的码。

#### 4.7.4 再次在飞书发消息验证

1. 飞书再发：`你好`。
2. 若 LLM Key 与 `openclaw onboard` 已配置，Agent A 应开始回复。
3. 若无回复，执行：

```bash
openclaw logs --follow
```

同时检查 `config/.env` 里 `ANTHROPIC_API_KEY` 或 `OPENAI_API_KEY` 是否已填，并曾运行 `openclaw onboard`。

#### 4.7.5 群聊（可选）

默认需要 **@机器人** 才会回复。把机器人拉进群后，发：

```text
@你的机器人名 你好
```

若完全无反应：检查 1.6 已发布、群已添加机器人、开放平台 **可用范围** 包含该群成员。

---

### 4.8 飞书接入检查清单（打勾即用）


| 序号  | 检查项                             | 如何确认                           |
| --- | ------------------------------- | ------------------------------ |
| 1   | App ID/Secret 已写入 `config/.env` | `grep FEISHU config/.env`      |
| 2   | `./scripts/deploy.sh` 已执行       | 存在 `~/.openclaw/openclaw.json` |
| 3   | Gateway 运行中                     | `openclaw gateway status`      |
| 4   | 长连接已保存                          | 开放平台事件订阅页显示已连接                 |
| 5   | 应用已发布                           | 版本管理为「已发布」                     |
| 6   | 配对已通过                           | `pairing approve` 成功           |
| 7   | 能收到回复                           | 飞书私聊有 AI 回复（需 LLM Key）         |


---

### 4.9 飞书阶段常见错误


| 现象                            | 原因                     | 处理                                                        |
| ----------------------------- | ---------------------- | --------------------------------------------------------- |
| 保存长连接失败                       | Gateway 未启动或 Secret 错误 | 第二节步骤 E；核对 Secret；`gateway restart`                    |
| `openclaw: command not found` | PATH 未加载               | `source ~/.bashrc` 或 `scripts/env.sh`                     |
| 搜不到机器人                        | 应用未发布或可见范围不含你          | 完成 4.2；管理后台检查应用可用范围                                       |
| 发了消息没反应                       | 未 pairing 或未 @         | 4.3.3 `pairing approve`；群聊要 @                             |
| 配对后仍不回复                       | 无 LLM API Key          | 完成本文第六节 + `openclaw onboard`                            |
| 日志 `app secret invalid`       | Secret 填错或已重置          | 开放平台重置 Secret，更新 `.env` 后 `deploy.sh` + `gateway restart` |


更细说明见 [OpenClaw 飞书文档](https://docs.openclaw.ai/channels/feishu)。

---

## 五、飞书补充配置

### OpenClaw 通道命令

```bash
openclaw channels login --channel feishu
# 手动：粘贴 App ID、App Secret

openclaw gateway restart
openclaw pairing list feishu
openclaw pairing approve feishu <CODE>
```

### 绑定 Agent A

默认 `config/openclaw.json5` 已将全部飞书 `default` 账号路由到 `agent-a`。

若需仅某用户 DM 进 A：

```json5
bindings: [
  {
    agentId: "agent-a",
    match: {
      channel: "feishu",
      peer: { kind: "direct", id: "ou_xxxxxxxx" },
    },
  },
],
```

`ou_` 从 `openclaw logs --follow` 或 pairing 列表获取。

### 语音消息

在 `openclaw.json` 配置 `tools.media.audio` 与转写模型（通常需 `OPENAI_API_KEY`）。  
未配置时 Agent 仍可能收到占位符，需用户补充文字说明。

### 群聊

默认需 @ 机器人。`groupPolicy: allowlist` 时把群 `oc_` ID 加入 `groupAllowFrom` 或 `groups.oc_xxx`。

---

## 六、LLM 凭证

**用途**：OpenClaw Gateway 主模型（Agent A 及 Cron Agent 推理）；`OPENAI_API_KEY` 还可用于飞书语音转写。

### 方案 A：DeepSeek（本项目默认，Anthropic 兼容端点）

1. 在 [DeepSeek 开放平台](https://platform.deepseek.com/) 注册并创建 API Key。
2. 写入 `config/.env`：

```bash
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_API_KEY="sk-..."
export OPENCLAW_DEFAULT_MODEL="deepseek/deepseek-v4-pro[1m]"
```

3. 运行 `./scripts/deploy.sh` 与 `openclaw gateway restart`。
4. 验证：`openclaw infer model run --model deepseek/deepseek-v4-pro[1m] --prompt "好"`

Provider 定义见 [`config/openclaw.json5`](../config/openclaw.json5) 中 `models.providers.deepseek`（`anthropic-messages` 适配器）。

**Rayin 备用**（OpenAI 兼容）：见 `config/.env` 与 `openclaw.json5` 中的注释块；`OPENCLAW_DEFAULT_MODEL` 改为 `rayin/gpt-5.3-codex` 后重新 `deploy.sh`。

### 方案 B：Anthropic 官方

1. 注册 [Anthropic Console](https://console.anthropic.com/)。
2. 完成计费/额度设置（需绑定支付方式或申请额度）。
3. 进入 **API Keys** → **Create Key** → 复制（以 `sk-ant-` 开头）。
4. 写入 `config/.env`：

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
export OPENCLAW_DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
```

1. 运行 `openclaw onboard`，在向导中选择 Anthropic 并粘贴 Key（会写入 `~/.openclaw/` 的 auth 配置）。

### 方案 C：OpenAI（主模型 + 语音转写二合一）

1. 登录 [OpenAI Platform](https://platform.openai.com/)。
2. **API keys** → **Create new secret key** → 复制（`sk-...`）。
3. 写入：

```bash
export OPENAI_API_KEY="sk-..."
# 若主模型也用 OpenAI，在 onboard 或 openclaw.json 中改 model
```

1. `openclaw onboard` 中选择 OpenAI provider。

### 语音转写（可选）

- 飞书语音消息需配置 `tools.media.audio`（见 OpenClaw 文档）。
- 通常复用 **同一个 `OPENAI_API_KEY`**（Whisper/转写接口）。
- 未配置时：Agent 可能只收到音频占位符，需用户补文字。

**注意**：不要把 Key 提交到 Git；`config/.env` 已在 [.gitignore](../.gitignore) 中忽略。

---

## 七、Google Stitch MCP

**用途**：`agent-design` 通过 Stitch 远程 MCP 生成 UI 设计。

### 3.1 获取 API Key

1. 打开 [stitch.withgoogle.com](https://stitch.withgoogle.com) 并登录。
2. 右上角头像 → **Stitch settings** → **API key** → **Create key**。
3. 立即复制 Key（只显示一次），写入 `config/.env`：

```bash
export STITCH_API_KEY="AQ.xxxxx"
```

### 3.2 部署到 OpenClaw

```bash
cd /home/wmx/workspace/test-pipeline
source config/.env
./scripts/deploy.sh
openclaw gateway restart
```

OpenClaw 会连接官方端点 `https://stitch.googleapis.com/mcp`，请求头带 `X-Goog-Api-Key`。

### 3.3 验证

```bash
openclaw mcp show stitch
openclaw logs --follow   # 不应再出现 stitch Connection closed
```

### 3.4 与项目配置对齐

[config/openclaw.json5](../config/openclaw.json5) 中 `mcp.servers.stitch` 使用 HTTP transport；`deploy.sh` 从 `STITCH_API_KEY` 注入 header。

---

<details>
<summary>备选：gcloud ADC（旧方式，一般不需要）</summary>

若你更倾向 OAuth / GCP 项目，可安装 gcloud 并启用 `stitch.googleapis.com`，使用 `npx stitch-mcp` + `GOOGLE_CLOUD_PROJECT`。本项目默认已改为 API Key 方式。

</details>

---

## 八、Claude Code CLI

**用途**：`agent-coder` / `agent-verifier` 通过 `scripts/claude-pipeline.sh` 调用 Claude Code 非交互模式（`claude --bare -p`）。

**验证约定**：验证阶段须先运行 `scripts/verify-pipeline.sh`（Docker 构建部署 + 探活），失败时通过 `fix_needed` 状态回流 coder。详见 [VERIFICATION.md](VERIFICATION.md)。

**与 OpenClaw 凭证隔离**：不得复用 `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL`；必须在 `config/.env` 中单独填写 `CLAUDE_CODE_*`。

### 4.1 确认已安装

```bash
source ~/.bashrc
claude --version
```

未安装时：`./scripts/install-ubuntu.sh` 或 `npm install -g @anthropic-ai/claude-code@latest`。

### 4.2 填写 `config/.env`

**DeepSeek（推荐，经 Claude Code Anthropic 兼容端点）**

在 `config/.env` 使用 `CLAUDE_CODE_*` 前缀；`deploy.sh` 会映射为 Claude Code 识别的环境变量名：

| `config/.env`（本项目） | 写入 `pipeline-settings.json` 的 `env` 键 | 说明 |
|-------------------------|-------------------------------------------|------|
| `CLAUDE_CODE_API_KEY` | `ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY` | DeepSeek API Key |
| `CLAUDE_CODE_BASE_URL` | `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic`（不带 `/v1`） |
| `CLAUDE_CODE_MODEL` | `ANTHROPIC_MODEL` | 主模型，如 `deepseek-v4-pro[1m]` |
| `CLAUDE_CODE_DEFAULT_OPUS_MODEL` | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus 档，默认同 `CLAUDE_CODE_MODEL` |
| `CLAUDE_CODE_DEFAULT_SONNET_MODEL` | `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet 档，默认同 `CLAUDE_CODE_MODEL` |
| `CLAUDE_CODE_DEFAULT_HAIKU_MODEL` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | 轻量模型，如 `deepseek-v4-flash` |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `CLAUDE_CODE_SUBAGENT_MODEL` | 子 Agent 模型，默认同 Haiku 档 |
| `CLAUDE_CODE_EFFORT_LEVEL` | `CLAUDE_CODE_EFFORT_LEVEL` | 推理力度，如 `max` |

示例（与 DeepSeek 官方 Claude Code 配置对应）：

```bash
export CLAUDE_CODE_API_KEY="sk-..."                              # → ANTHROPIC_AUTH_TOKEN
export CLAUDE_CODE_BASE_URL="https://api.deepseek.com/anthropic"
export CLAUDE_CODE_MODEL="deepseek-v4-pro[1m]"
export CLAUDE_CODE_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
export CLAUDE_CODE_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
export CLAUDE_CODE_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_EFFORT_LEVEL="max"
```

**Anthropic 官方 API**（若不用 DeepSeek）：

```bash
export CLAUDE_CODE_API_KEY="sk-ant-..."
export CLAUDE_CODE_BASE_URL="https://api.anthropic.com"
export CLAUDE_CODE_MODEL="claude-sonnet-4-6"
export CLAUDE_CODE_DEFAULT_OPUS_MODEL="claude-opus-4-6"
export CLAUDE_CODE_DEFAULT_SONNET_MODEL="claude-sonnet-4-6"
export CLAUDE_CODE_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export CLAUDE_CODE_SUBAGENT_MODEL="claude-haiku-4-5-20251001"
export CLAUDE_CODE_EFFORT_LEVEL="high"
```

未单独设置的 `*_OPUS_MODEL` / `*_SONNET_MODEL` 会回退到 `CLAUDE_CODE_MODEL`；`CLAUDE_CODE_SUBAGENT_MODEL` 默认回退到 `CLAUDE_CODE_DEFAULT_HAIKU_MODEL`。

### 4.3 部署与验证

```bash
./scripts/deploy.sh   # 生成 pipeline-settings.json 并同步到 ~/.claude/settings.json
claude --bare -p "只回复 hello"   # 或 claude（交互式，无需 --settings）
```

### 4.4 与流水线配置的关系

- 凭证写入 `config/.env` 的 `CLAUDE_CODE_*`，由 `deploy.sh` 渲染到 `~/.claude/pipeline-settings.json` 并同步 `~/.claude/settings.json`
- Agent 通过 `claude-pipeline.sh implement|verify|verify-fix` 调用，显式传 `--settings`

---

## 九、Codex CLI（可选）

**用途**：历史方案；当前流水线默认使用 Claude Code。若需 Codex，见下方步骤。

### 5.1 确认已安装

```bash
source ~/.bashrc   # 或 source scripts/env.sh
codex --version
```

### 5.2 方式一：ChatGPT 登录（推荐，含订阅额度）

```bash
codex login
```

1. 终端提示打开浏览器。
2. 使用 **ChatGPT 账号**（需有 Codex 可用权限的套餐，见 [OpenAI Codex 文档](https://developers.openai.com/codex)）。
3. 登录成功后凭证缓存在 `~/.codex/` 下（如 `auth.json`）。

**无图形界面服务器**：

```bash
codex login --device-auth
```

按提示在另一台设备打开 URL 输入设备码；需在 ChatGPT 账户设置中启用 Device Code 登录（工作区由管理员开启）。

### 5.3 方式二：API Key（CI/纯 API 计费）

1. 在 [OpenAI API Keys](https://platform.openai.com/api-keys) 创建 Key。
2. 登录：

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
# 或
echo "sk-..." | codex login --with-api-key
```

API Key 计费与 ChatGPT 订阅**分开**；需账户有 Codex 可用模型权限。

### 5.4 验证

```bash
codex login status
codex exec -p ci "echo hello" -o /tmp/codex-test.md
```

### 5.5 与流水线配置的关系

- 登录信息：**不写入** `config/.env`（由 Codex 自己管理）。
- 沙箱与模型：[config/codex-profiles.toml](../config/codex-profiles.toml) 的 `[profiles.ci]` 在 `deploy.sh` 时合并到 `~/.codex/config.toml`。

---

## 十、汇总部署

复制模板并填写：

```bash
cp config/env.example config/.env
nano config/.env
```

最小示例：

```bash
export PIPELINE_ROOT="/home/wmx/workspace/test-pipeline"
export WORKSPACE_ROOT="/home/wmx/workspace/pipeline-workspace"
export FEISHU_APP_ID="cli_xxx"
export FEISHU_APP_SECRET="xxx"
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENCLAW_DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
export STITCH_API_KEY="your-stitch-api-key"
export CLAUDE_CODE_API_KEY="sk-..."
export CLAUDE_CODE_BASE_URL="https://api.deepseek.com/anthropic"
export CLAUDE_CODE_MODEL="deepseek-v4-pro[1m]"
export CLAUDE_CODE_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_EFFORT_LEVEL="max"
# OPENAI_API_KEY 仅在使用 OpenAI 主模型或语音转写时需要
```

然后按顺序：

```bash
openclaw onboard --install-daemon    # 首次：配置 Gateway、模型、daemon
./scripts/deploy.sh
openclaw channels login --channel feishu
openclaw gateway restart
./scripts/setup-cron.sh
# codex login                          # 可选
```

---

---

## 十一、验收检查表

| # | 检查项 | 命令 / 位置 |
|---|--------|-------------|
| 1 | `openclaw` 可用 | `openclaw --version` |
| 2 | 配置文件存在 | `~/.openclaw/openclaw.json` |
| 3 | 飞书插件已装 | `openclaw status` → Feishu OK |
| 4 | Gateway 运行 | `openclaw gateway status` → running |
| 5 | WebSocket 已启 | 日志有 `WebSocket client started` |
| 6 | App ID/Secret 已写入 | `grep FEISHU config/.env` |
| 7 | 长连接已保存 | 开放平台事件订阅页显示已连接 |
| 8 | 应用已发布 | 版本管理 → 已发布 |
| 9 | 配对已通过 | `pairing approve` 成功 |
| 10 | 能对话 | 飞书收到 AI 回复（需 LLM Key） |

---

## 十二、常见问题

### Q1: `openclaw: command not found`

```bash
export PATH="$HOME/.local/node/bin:$HOME/.local/npm-global/bin:$PATH"
source ~/.bashrc
```

确认 `~/.bashrc` 末尾有：

```bash
export PATH="$HOME/.local/node/bin:$HOME/.local/npm-global/bin:$PATH"
```

---

### Q2: 日志里 `Gateway service disabled`

Gateway 未启动。执行：

```bash
openclaw gateway install
openclaw gateway start
openclaw gateway status
```

---

### Q3: `Local Gateway RPC unavailable`

同上，先 `gateway start`。`openclaw logs` 在 Gateway 未运行时会读 `/tmp/openclaw/*.log` 并提示 disabled。

---

### Q4: Feishu 显示 `plugin not installed`

```bash
openclaw plugins install @openclaw/feishu
openclaw gateway restart
openclaw status
```

---

### Q5: 飞书保存长连接失败

顺序必须是：**先** A6 Gateway + WebSocket 正常 → **再** B2 网页保存。

---

### Q6: `gateway token missing`（CLI 连 Gateway）

Gateway 启用了 token 认证。优先用：

```bash
journalctl --user -u openclaw-gateway.service -f
```

或确保使用较新的 `openclaw logs --follow`（会自动带本地 token）。

---

### Q7: `device token scope mismatch` / `EMBEDDED FALLBACK`

部署完成后跑 `openclaw agent --agent agent-a --message "回复 OK"` 时，若出现：

```text
device token scope mismatch (re-pair or approve scope upgrade)
EMBEDDED FALLBACK: Gateway agent failed; running embedded agent
```

说明本机 CLI 设备权限不足（常见：只有 `operator.read`，缺 `operator.write`）。Agent 可能仍通过 embedded 模式回复，但 **Gateway 链路未通**，飞书/Cron 等经 Gateway 的能力可能异常。

**处理**：按 [env-troubleshoot.md §2.8.1](../env-troubleshoot.md#281-device-token-scope-mismatch) 批准 scope 升级；或打开 **http://127.0.0.1:18789/** Control UI 批准。

---

### 凭证与其他


| 问题                               | 处理                                                               |
| -------------------------------- | ---------------------------------------------------------------- |
| 飞书保存长连接失败                        | 先 `openclaw gateway restart`，确保 Gateway 在线后再在开放平台保存              |
| 机器人无回复                           | 检查应用已发布、`im.message.receive_v1` 已订阅、执行 `pairing approve`         |
| Stitch MCP 401/403               | 在 Stitch settings 重新 Create key，更新 `STITCH_API_KEY` 并 `./scripts/deploy.sh` |
| Claude Code 401/连接失败 | 检查 `CLAUDE_CODE_*` 已填、`CLAUDE_CODE_BASE_URL` 不带 `/v1`，并 `./scripts/deploy.sh` |
| `codex login` 浏览器打不开             | 使用 `codex login --device-auth` 或 API Key 管道登录（Codex 可选） |
| OpenClaw 与 Codex 都要 OpenAI Key 吗 | 可以：OpenClaw 用 Anthropic，Codex 单独 `codex login`；语音转写仍需 OpenAI Key |


---

---

## 十三、相关文档

- [README.md](../README.md) — 架构、状态机、Cron dispatch 卡死重试、日常运维
- [env-troubleshoot.md](../env-troubleshoot.md) — `.env` 变更重启、LLM 连通、scope mismatch
- [config/env.example](../config/env.example) — 环境变量模板
- [OpenClaw 飞书文档](https://docs.openclaw.ai/channels/feishu)
