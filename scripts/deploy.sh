#!/usr/bin/env bash
# 将本仓库配置部署到 ~/.openclaw 并准备 Agent 工作区
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env

OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
mkdir -p "$OPENCLAW_HOME" "${PIPELINE_ROOT}/pipeline/feedback/inbox" \
  "${PIPELINE_ROOT}/pipeline/feedback/raw" \
  "${PIPELINE_ROOT}/pipeline/delivered"

log "PIPELINE_ROOT=$PIPELINE_ROOT"
log "OPENCLAW_HOME=$OPENCLAW_HOME"

# 工作区：替换占位符
for ws in agent-a agent-design agent-coder agent-verifier agent-feedback; do
  dest="${PIPELINE_ROOT}/workspaces/${ws}"
  substitute_workspace_files "$dest"
done

# openclaw.json：环境变量替换后写入
if [[ ! -f "${REPO_ROOT}/config/.env" ]]; then
  echo "请先复制 config/env.example → config/.env 并填写密钥" >&2
  exit 1
fi

tmp_cfg="$(mktemp)"
export_vars='${PIPELINE_ROOT} ${FEISHU_APP_ID} ${FEISHU_APP_SECRET} ${STITCH_API_KEY} ${OPENCLAW_DEFAULT_MODEL} ${ANTHROPIC_BASE_URL} ${ANTHROPIC_API_KEY}'
if command -v envsubst >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  envsubst "$export_vars" < "${REPO_ROOT}/config/openclaw.json5" > "$tmp_cfg"
else
  default_model="${OPENCLAW_DEFAULT_MODEL:-rayin/gpt-5.3-codex}"
  sed -e "s|\${PIPELINE_ROOT}|${PIPELINE_ROOT}|g" \
      -e "s|\${FEISHU_APP_ID}|${FEISHU_APP_ID:-}|g" \
      -e "s|\${FEISHU_APP_SECRET}|${FEISHU_APP_SECRET:-}|g" \
      -e "s|\${STITCH_API_KEY}|${STITCH_API_KEY:-}|g" \
      -e "s|\${OPENCLAW_DEFAULT_MODEL}|${default_model}|g" \
      -e "s|\${ANTHROPIC_BASE_URL}|${ANTHROPIC_BASE_URL:-}|g" \
      -e "s|\${ANTHROPIC_API_KEY}|${ANTHROPIC_API_KEY:-}|g" \
      "${REPO_ROOT}/config/openclaw.json5" > "$tmp_cfg"
fi

if [[ -f "${OPENCLAW_HOME}/openclaw.json" ]]; then
  cp "${OPENCLAW_HOME}/openclaw.json" "${OPENCLAW_HOME}/openclaw.json.bak.$(date +%s)"
  log "已备份原 openclaw.json"
fi
cp "$tmp_cfg" "${OPENCLAW_HOME}/openclaw.json"
rm -f "$tmp_cfg"

# Codex profile
mkdir -p "$HOME/.codex"
if [[ -f "$HOME/.codex/config.toml" ]] && ! grep -q '\[profiles.ci\]' "$HOME/.codex/config.toml"; then
  sed "s|{{PIPELINE_ROOT}}|${PIPELINE_ROOT}|g" "${REPO_ROOT}/config/codex-profiles.toml" >> "$HOME/.codex/config.toml"
  log "已追加 [profiles.ci] 到 ~/.codex/config.toml"
elif [[ ! -f "$HOME/.codex/config.toml" ]]; then
  sed "s|{{PIPELINE_ROOT}}|${PIPELINE_ROOT}|g" "${REPO_ROOT}/config/codex-profiles.toml" > "$HOME/.codex/config.toml"
  log "已创建 ~/.codex/config.toml"
fi

# MCP stitch（HTTP + API Key，无需 gcloud）
if command -v openclaw >/dev/null 2>&1 && [[ -n "${STITCH_API_KEY:-}" ]]; then
  openclaw mcp set stitch "$(cat <<EOF
{"url":"https://stitch.googleapis.com/mcp","transport":"streamable-http","headers":{"X-Goog-Api-Key":"${STITCH_API_KEY}"}}
EOF
)" 2>/dev/null || true
fi

# Claude Code pipeline settings（独立凭证，不复用 OpenClaw ANTHROPIC_*）
if [[ -z "${CLAUDE_CODE_API_KEY:-}" ]]; then
  log "警告: CLAUDE_CODE_API_KEY 未设置，agent-coder/verifier 将无法运行 Claude Code"
elif [[ -z "${CLAUDE_CODE_BASE_URL:-}" ]]; then
  log "警告: CLAUDE_CODE_BASE_URL 未设置，agent-coder/verifier 将无法运行 Claude Code"
else
  mkdir -p "$HOME/.claude"
  _cc_primary="${CLAUDE_CODE_MODEL:-${CLAUDE_CODE_DEFAULT_MODEL:-claude-sonnet-4-6}}"
  export CLAUDE_CODE_BASE_URL
  export CLAUDE_CODE_API_KEY
  export CLAUDE_CODE_MODEL="${CLAUDE_CODE_MODEL:-$_cc_primary}"
  export CLAUDE_CODE_DEFAULT_OPUS_MODEL="${CLAUDE_CODE_DEFAULT_OPUS_MODEL:-$_cc_primary}"
  export CLAUDE_CODE_DEFAULT_SONNET_MODEL="${CLAUDE_CODE_DEFAULT_SONNET_MODEL:-$_cc_primary}"
  export CLAUDE_CODE_DEFAULT_HAIKU_MODEL="${CLAUDE_CODE_DEFAULT_HAIKU_MODEL:-deepseek-v4-flash}"
  export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-${CLAUDE_CODE_DEFAULT_HAIKU_MODEL:-deepseek-v4-flash}}"
  export CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-max}"
  _cc_export_vars='${CLAUDE_CODE_BASE_URL} ${CLAUDE_CODE_API_KEY} ${CLAUDE_CODE_MODEL} ${CLAUDE_CODE_DEFAULT_OPUS_MODEL} ${CLAUDE_CODE_DEFAULT_SONNET_MODEL} ${CLAUDE_CODE_DEFAULT_HAIKU_MODEL} ${CLAUDE_CODE_SUBAGENT_MODEL} ${CLAUDE_CODE_EFFORT_LEVEL}'
  if command -v envsubst >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    envsubst "$_cc_export_vars" < "${REPO_ROOT}/config/claude-settings.json.template" > "$HOME/.claude/pipeline-settings.json"
  else
    log "错误: 需要 envsubst 生成 pipeline-settings.json（apt install gettext-base）" >&2
    exit 1
  fi
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.bak.$(date +%s)"
    log "已备份原 ~/.claude/settings.json"
  fi
  cp "$HOME/.claude/pipeline-settings.json" "$HOME/.claude/settings.json"
  log "已生成 ~/.claude/pipeline-settings.json 并同步到 ~/.claude/settings.json（可直接运行 claude）"
fi

log "部署完成。下一步:"
echo "  1. openclaw onboard          # 若尚未初始化"
echo "  2. openclaw channels login --channel feishu"
echo "  3. openclaw gateway restart"
echo "  4. ./scripts/setup-cron.sh"
echo "  5. 填写 config/.env 中 CLAUDE_CODE_* 后重新 deploy（若尚未填写）"
