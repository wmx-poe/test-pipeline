#!/usr/bin/env bash
# Ubuntu 22.04+ 从零安装依赖：Node、OpenClaw、Claude Code、ffmpeg（Stitch 用 API Key，无需 gcloud）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export DEBIAN_FRONTEND=noninteractive

log() { echo "[install] $*"; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
  command -v sudo >/dev/null || { echo "需要 sudo"; exit 1; }
fi

log "更新 apt..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq curl ca-certificates git build-essential ffmpeg gettext-base jq

# Node.js 22 LTS（优先用户目录，无需 sudo）
install_node_user() {
  local NODE_DIR="${HOME}/.local/node"
  local VER="v22.22.0"
  mkdir -p "$NODE_DIR"
  if ! command -v wget >/dev/null 2>&1; then
    $SUDO apt-get install -y -qq wget
  fi
  log "安装 Node ${VER} 到 ${NODE_DIR}..."
  wget -q "https://nodejs.org/dist/${VER}/node-${VER}-linux-x64.tar.xz" -O /tmp/node.tar.xz
  tar -xJf /tmp/node.tar.xz -C "$NODE_DIR" --strip-components=1
  export PATH="${NODE_DIR}/bin:${PATH}"
  npm config set prefix "${HOME}/.local/npm-global"
  export PATH="${HOME}/.local/npm-global/bin:${PATH}"
}

if [[ -x "${HOME}/.local/node/bin/node" ]]; then
  export PATH="${HOME}/.local/node/bin:${HOME}/.local/npm-global/bin:${PATH}"
elif command -v node >/dev/null 2>&1 && [[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]]; then
  :
elif command -v curl >/dev/null 2>&1 && [[ -n "${SUDO}" ]]; then
  log "安装 Node.js 22 (apt)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
  $SUDO apt-get install -y -qq nodejs
else
  install_node_user
fi

# 持久化 PATH
MARKER='# openclaw-pipeline PATH'
grep -qF "$MARKER" "${HOME}/.bashrc" 2>/dev/null || cat >> "${HOME}/.bashrc" <<'EOF'

# openclaw-pipeline PATH
export PATH="$HOME/.local/node/bin:$HOME/.local/npm-global/bin:$PATH"
EOF

export PATH="${HOME}/.local/node/bin:${HOME}/.local/npm-global/bin:${PATH}"
log "Node $(node -v) npm $(npm -v)"

# OpenClaw + Claude Code / Codex CLI（全局）
npm config set prefix "${HOME}/.local/npm-global" 2>/dev/null || true
export PATH="${HOME}/.local/npm-global/bin:${PATH}"

if ! command -v openclaw >/dev/null 2>&1; then
  log "安装 OpenClaw..."
  npm install -g openclaw@latest
fi
log "OpenClaw $(openclaw --version 2>/dev/null || echo '?')"

if ! command -v codex >/dev/null 2>&1; then
  log "安装 Codex CLI（可选）..."
  npm install -g @openai/codex@latest
fi
log "Codex $(codex --version 2>/dev/null || echo '未安装（可选）')"

if ! command -v claude >/dev/null 2>&1; then
  log "安装 Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code@latest
fi
log "Claude Code $(claude --version 2>/dev/null || echo '?')"

# 飞书通道插件（OpenClaw 2026.x 需单独安装）
if openclaw plugins list 2>/dev/null | grep -qE 'feishu|@openclaw/feishu'; then
  log "飞书插件已安装"
else
  log "安装飞书插件 @openclaw/feishu..."
  openclaw plugins install @openclaw/feishu || log "飞书插件安装失败，稍后手动: openclaw plugins install @openclaw/feishu"
fi

# Google Cloud SDK（可选；Stitch 默认用 API Key，无需 gcloud）
# 若仍要走 gcloud ADC：INSTALL_GCLOUD=1 ./scripts/install-ubuntu.sh
if [[ "${INSTALL_GCLOUD:-0}" == "1" ]]; then
GCLOUD_DIR="${HOME}/google-cloud-sdk"
GCLOUD_MARKER='# google-cloud-sdk PATH'
if [[ -x "${GCLOUD_DIR}/bin/gcloud" ]]; then
  log "Google Cloud CLI 已存在: ${GCLOUD_DIR}/bin/gcloud"
elif [[ -x /tmp/google-cloud-sdk/bin/gcloud ]]; then
  log "迁移 /tmp/google-cloud-sdk → ${GCLOUD_DIR}..."
  rm -rf "${GCLOUD_DIR}"
  mv /tmp/google-cloud-sdk "${GCLOUD_DIR}"
else
  log "安装 Google Cloud CLI 到 ${GCLOUD_DIR}..."
  curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz -o /tmp/gcloud.tar.gz
  tar -xzf /tmp/gcloud.tar.gz -C "${HOME}"
  "${GCLOUD_DIR}/install.sh" --quiet --usage-reporting false --path-update false --command-completion false
fi
grep -qF "$GCLOUD_MARKER" "${HOME}/.bashrc" 2>/dev/null || cat >> "${HOME}/.bashrc" <<'EOF'

# google-cloud-sdk PATH
if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then . "$HOME/google-cloud-sdk/path.bash.inc"; fi
EOF
sed -i "\|/tmp/google-cloud-sdk/path.bash.inc|d" "${HOME}/.bashrc" 2>/dev/null || true
# shellcheck disable=SC1091
[[ -f "${GCLOUD_DIR}/path.bash.inc" ]] && source "${GCLOUD_DIR}/path.bash.inc"

log "启用 Stitch MCP API（需已 gcloud auth login）..."
if command -v gcloud >/dev/null 2>&1; then
  gcloud beta services mcp enable stitch.googleapis.com 2>/dev/null || \
    log "跳过 stitch API（请手动: gcloud beta services mcp enable stitch.googleapis.com）"
fi
else
  log "跳过 Google Cloud CLI（Stitch 使用 STITCH_API_KEY，见 config/env.example）"
fi

# 环境文件模板
if [[ ! -f "${REPO_ROOT}/config/.env" ]]; then
  cp "${REPO_ROOT}/config/env.example" "${REPO_ROOT}/config/.env"
  sed -i "s|/home/wmx/workspace/test-pipeline|${REPO_ROOT}|g" "${REPO_ROOT}/config/.env"
  log "已创建 config/.env，请编辑密钥"
fi

chmod +x "${REPO_ROOT}/scripts/"*.sh

log "基础安装完成。"
cat <<'EOF'

后续步骤（以部署用户执行，非 root）:
  完整图文流程: docs/SETUP-FEISHU.md

  1. 编辑 config/.env（飞书、API Key、STITCH_API_KEY、CLAUDE_CODE_*）
  2. openclaw onboard --install-daemon
  3. ./scripts/setup-feishu.sh          # deploy + 飞书插件 + gateway
  4. 飞书开放平台保存「长连接」并发布应用
  5. openclaw pairing approve feishu <码>
  6. codex login                       # 可选
  7. ./scripts/setup-cron.sh

EOF
