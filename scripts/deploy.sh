#!/usr/bin/env bash
# 将本仓库配置部署到 ~/.openclaw 并准备 Agent 工作区
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env

OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"

# 裸模型 ID（如 deepseek-v4-flash）转为 OpenClaw 引用（deepseek/deepseek-v4-flash）
openclaw_model_ref() {
  local id="$1"
  [[ -n "$id" ]] || return 0
  if [[ "$id" == */* ]]; then
    printf '%s\n' "$id"
  else
    local provider="${OPENCLAW_MODEL_PROVIDER:-}"
    if [[ -z "$provider" && -n "${OPENCLAW_DEFAULT_MODEL:-}" && "${OPENCLAW_DEFAULT_MODEL}" == */* ]]; then
      provider="${OPENCLAW_DEFAULT_MODEL%%/*}"
    fi
    provider="${provider:-deepseek}"
    printf '%s\n' "${provider}/${id}"
  fi
}

# 将 config/.env 中 CLAUDE_CODE_* / OPENCLAW_* 模型同步到 OpenClaw agents.defaults
merge_openclaw_model_allowlist() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 0

  local _cc_primary="${CLAUDE_CODE_MODEL:-${CLAUDE_CODE_DEFAULT_MODEL:-}}"
  local _cc_opus="${CLAUDE_CODE_DEFAULT_OPUS_MODEL:-$_cc_primary}"
  local _cc_sonnet="${CLAUDE_CODE_DEFAULT_SONNET_MODEL:-$_cc_primary}"
  local _cc_haiku="${CLAUDE_CODE_DEFAULT_HAIKU_MODEL:-deepseek-v4-flash}"
  local _cc_sub="${CLAUDE_CODE_SUBAGENT_MODEL:-$_cc_haiku}"
  local _cc_effort="${CLAUDE_CODE_EFFORT_LEVEL:-max}"

  local ref_default ref_cron_pro ref_cron_flash
  local ref_primary ref_opus ref_sonnet ref_haiku ref_sub

  ref_default="$(openclaw_model_ref "${OPENCLAW_DEFAULT_MODEL:-}")"
  ref_cron_pro="$(openclaw_model_ref "${OPENCLAW_CRON_MODEL_PRO:-deepseek/deepseek-v4-pro[1m]}")"
  ref_cron_flash="$(openclaw_model_ref "${OPENCLAW_CRON_MODEL_FLASH:-deepseek/deepseek-v4-flash}")"
  ref_primary="$(openclaw_model_ref "$_cc_primary")"
  ref_opus="$(openclaw_model_ref "$_cc_opus")"
  ref_sonnet="$(openclaw_model_ref "$_cc_sonnet")"
  ref_haiku="$(openclaw_model_ref "$_cc_haiku")"
  ref_sub="$(openclaw_model_ref "$_cc_sub")"

  local openclaw_pkg="${OPENCLAW_PKG:-$(npm root -g 2>/dev/null)/openclaw}"
  if [[ ! -d "${openclaw_pkg}/node_modules/json5" ]] || ! command -v node >/dev/null 2>&1; then
    log "警告: 无法合并 OpenClaw 模型配置（需要 node 与 openclaw 自带 json5）"
    return 0
  fi

  OPENCLAW_PKG="$openclaw_pkg" CFG="$cfg" EFFORT="$_cc_effort" \
    REF_DEFAULT="$ref_default" REF_CRON_PRO="$ref_cron_pro" REF_CRON_FLASH="$ref_cron_flash" \
    REF_PRIMARY="$ref_primary" REF_OPUS="$ref_opus" REF_SONNET="$ref_sonnet" \
    REF_HAIKU="$ref_haiku" REF_SUB="$ref_sub" \
    node <<'NODE'
const JSON5 = require(process.env.OPENCLAW_PKG + '/node_modules/json5');
const fs = require('fs');

function mergeEntry(models, ref, patch) {
  if (!ref) return;
  const existing = models[ref] || {};
  const merged = { ...existing, ...patch };
  if (existing.params || patch.params) {
    merged.params = { ...(existing.params || {}), ...(patch.params || {}) };
  }
  models[ref] = merged;
}

const cfgPath = process.env.CFG;
const effort = process.env.EFFORT || 'max';
const refs = {
  default: process.env.REF_DEFAULT || '',
  cronPro: process.env.REF_CRON_PRO || '',
  cronFlash: process.env.REF_CRON_FLASH || '',
  primary: process.env.REF_PRIMARY || '',
  opus: process.env.REF_OPUS || '',
  sonnet: process.env.REF_SONNET || '',
  haiku: process.env.REF_HAIKU || '',
  sub: process.env.REF_SUB || '',
};

const doc = JSON5.parse(fs.readFileSync(cfgPath, 'utf8'));
doc.agents = doc.agents || {};
doc.agents.defaults = doc.agents.defaults || {};
const models = { ...(doc.agents.defaults.models || {}) };
const effortParams = { thinking: effort, effort };

for (const ref of [refs.default, refs.cronPro, refs.cronFlash, refs.sub]) {
  mergeEntry(models, ref, {});
}

if (refs.opus) {
  mergeEntry(models, refs.opus, { alias: 'opus', params: { ...effortParams } });
}
if (refs.sonnet && refs.sonnet !== refs.opus) {
  mergeEntry(models, refs.sonnet, { alias: 'sonnet' });
}
if (refs.haiku && refs.haiku !== refs.opus && refs.haiku !== refs.sonnet) {
  mergeEntry(models, refs.haiku, { alias: 'haiku' });
}
if (refs.primary && refs.primary !== refs.opus) {
  mergeEntry(models, refs.primary, { params: { ...effortParams } });
}

doc.agents.defaults.models = models;

if (refs.sub) {
  doc.agents.defaults.subagents = {
    ...(doc.agents.defaults.subagents || {}),
    model: refs.sub,
  };
}

fs.writeFileSync(cfgPath, JSON.stringify(doc, null, 2) + '\n');
const summary = [
  refs.opus && `opus=${refs.opus}`,
  refs.sonnet && refs.sonnet !== refs.opus && `sonnet=${refs.sonnet}`,
  refs.haiku && `haiku=${refs.haiku}`,
  refs.sub && `subagent=${refs.sub}`,
  `effort=${effort}`,
].filter(Boolean).join(', ');
console.log(summary);
NODE

  log "OpenClaw 模型配置已合并（opus=${ref_opus:-} subagent=${ref_sub:-} effort=${_cc_effort}）"
}

mkdir -p "$OPENCLAW_HOME" "${WORKSPACE_ROOT}"

log "PIPELINE_ROOT=$PIPELINE_ROOT"
log "WORKSPACE_ROOT=$WORKSPACE_ROOT"
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
  default_model="${OPENCLAW_DEFAULT_MODEL:-deepseek/deepseek-v4-pro[1m]}"
  # Rayin 备用默认：rayin/gpt-5.3-codex
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
merge_openclaw_model_allowlist "${OPENCLAW_HOME}/openclaw.json"

# Codex profile
mkdir -p "$HOME/.codex"
if [[ -f "$HOME/.codex/config.toml" ]] && ! grep -q '\[profiles.ci\]' "$HOME/.codex/config.toml"; then
  sed "s|{{PIPELINE_ROOT}}|${PIPELINE_ROOT}|g; s|{{WORKSPACE_ROOT}}|${WORKSPACE_ROOT}|g" "${REPO_ROOT}/config/codex-profiles.toml" >> "$HOME/.codex/config.toml"
  log "已追加 [profiles.ci] 到 ~/.codex/config.toml"
elif [[ ! -f "$HOME/.codex/config.toml" ]]; then
  sed "s|{{PIPELINE_ROOT}}|${PIPELINE_ROOT}|g; s|{{WORKSPACE_ROOT}}|${WORKSPACE_ROOT}|g" "${REPO_ROOT}/config/codex-profiles.toml" > "$HOME/.codex/config.toml"
  log "已创建 ~/.codex/config.toml"
fi

# MCP stitch（HTTP + API Key，无需 gcloud）
if command -v openclaw >/dev/null 2>&1 && [[ -n "${STITCH_API_KEY:-}" ]]; then
  openclaw mcp set stitch "$(cat <<EOF
{"url":"https://stitch.googleapis.com/mcp","transport":"streamable-http","headers":{"X-Goog-Api-Key":"${STITCH_API_KEY}"}}
EOF
)" 2>/dev/null || true
  # openclaw mcp set 会 merge 写回 openclaw.json，可能覆盖 agents.defaults.models
  merge_openclaw_model_allowlist "${OPENCLAW_HOME}/openclaw.json"
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
