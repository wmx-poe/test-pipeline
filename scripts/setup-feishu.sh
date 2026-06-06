#!/usr/bin/env bash
# OpenClaw + 飞书插件 + Gateway 一键配置（服务器侧）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env
require_cmd openclaw

log "PIPELINE_ROOT=$PIPELINE_ROOT"

if [[ ! -f "${REPO_ROOT}/config/.env" ]]; then
  echo "请先创建并填写 config/.env（FEISHU_APP_ID / FEISHU_APP_SECRET）" >&2
  exit 1
fi

log "1/4 deploy.sh — 写入 openclaw.json"
"${SCRIPT_DIR}/deploy.sh"

log "2/4 安装飞书插件 @openclaw/feishu"
if openclaw plugins list 2>/dev/null | grep -q feishu; then
  log "飞书插件已存在，跳过 install"
else
  openclaw plugins install @openclaw/feishu
fi

log "3/4 安装并启动 Gateway"
if ! systemctl --user is-enabled openclaw-gateway.service &>/dev/null; then
  openclaw gateway install || true
fi
openclaw gateway restart || openclaw gateway start

sleep 5

log "4/4 状态检查"
openclaw gateway status || true
echo "---"
openclaw status 2>&1 | sed -n '/Channels/,/Sessions/p' || openclaw status
if ! openclaw status 2>&1 | grep -qi feishu; then
  log "警告: 未检测到 Feishu 通道。请确认: openclaw plugins install @openclaw/feishu && openclaw gateway restart"
fi

cat <<EOF

服务器侧配置完成。请到飞书开放平台：
  1. 事件订阅 → 长连接 → im.message.receive_v1 → 保存
  2. 版本管理与发布 → 发布应用
  3. 飞书私聊机器人 → openclaw pairing approve feishu <码>

详见: docs/GUIDE.md
EOF
