# 飞书接入清单

完整密钥获取流程见 [CREDENTIALS.md](CREDENTIALS.md) 第 1 节。  
**安装 + 飞书连接一步步命令**见 [SETUP-FEISHU.md](SETUP-FEISHU.md)。

## 开放平台

1. 创建自建应用并发布  
2. **机器人**能力开启  
3. **事件订阅** → 使用长连接（WebSocket），不要仅用 Webhook（除非你做公网反代）  
4. 订阅 `im.message.receive_v1`  
5. 申请并开通消息相关权限  

## OpenClaw

```bash
openclaw channels login --channel feishu
# 手动：粘贴 App ID、App Secret
# 或 QR 创建（国内飞书 App 扫不了则改手动）

openclaw gateway restart
openclaw pairing list feishu
openclaw pairing approve feishu <CODE>
```

## 绑定 Agent A

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

## 语音消息

在 `openclaw.json` 配置 `tools.media.audio` 与转写模型（通常需 `OPENAI_API_KEY`）。  
未配置时 Agent 仍可能收到占位符，需用户补充文字说明。

## 群聊

默认需 @ 机器人。`groupPolicy: allowlist` 时把群 `oc_` ID 加入 `groupAllowFrom` 或 `groups.oc_xxx`。
