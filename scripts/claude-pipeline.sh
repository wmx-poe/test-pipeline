#!/usr/bin/env bash
# Claude Code 流水线封装（agent-coder / agent-verifier）
# 用法: claude-pipeline.sh <implement|verify|verify-fix|resume> <job-src-dir> "<prompt>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env

SETTINGS_FILE="${HOME}/.claude/pipeline-settings.json"

require_claude_env() {
  if [[ -z "${CLAUDE_CODE_API_KEY:-}" ]]; then
    echo "缺少 CLAUDE_CODE_API_KEY，请在 config/.env 中填写（与 OpenClaw ANTHROPIC_API_KEY 独立）" >&2
    exit 1
  fi
  if [[ -z "${CLAUDE_CODE_BASE_URL:-}" ]]; then
    echo "缺少 CLAUDE_CODE_BASE_URL，请在 config/.env 中填写（不带 /v1 后缀）" >&2
    exit 1
  fi
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "缺少 $SETTINGS_FILE，请先运行 ./scripts/deploy.sh" >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "缺少命令: $cmd（运行 ./scripts/install-ubuntu.sh 安装）" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
用法: claude-pipeline.sh <mode> <job-src-dir> "<prompt>"

mode:
  implement   实现代码（可写）
  verify      验证（只读）
  verify-fix  验证后修复（可写）
  resume      续跑上一轮会话

示例:
  claude-pipeline.sh implement pipeline/jobs/job-xxx/src "根据 ../spec.md 实现功能"
EOF
  exit 1
}

[[ $# -ge 3 ]] || usage
MODE="$1"
SRC_DIR="$2"
PROMPT="$3"

require_claude_env
require_cmd claude

if [[ ! -d "$SRC_DIR" ]]; then
  echo "目录不存在: $SRC_DIR" >&2
  exit 1
fi

REPORTS_DIR="$(cd "$SRC_DIR/.." && pwd)/reports"
mkdir -p "$REPORTS_DIR"

run_claude() {
  local permission_mode="$1"
  local allowed_tools="$2"
  local output_file="$3"
  shift 3
  local extra_args=("$@")

  (
    cd "$SRC_DIR"
    claude --bare -p "$PROMPT" \
      --settings "$SETTINGS_FILE" \
      --permission-mode "$permission_mode" \
      --allowedTools "$allowed_tools" \
      "${extra_args[@]}" \
      > "$output_file"
  )
}

case "$MODE" in
  implement)
    run_claude acceptEdits "Bash,Read,Edit,Glob,Grep" "${REPORTS_DIR}/claude-implement-last.md"
    ;;
  verify)
    run_claude dontAsk "Bash,Read,Glob,Grep" "${REPORTS_DIR}/verify.md"
    ;;
  verify-fix)
    run_claude acceptEdits "Bash,Read,Edit,Glob,Grep" "${REPORTS_DIR}/verify-fix.md"
    ;;
  resume)
    (
      cd "$SRC_DIR"
      claude --bare -p "$PROMPT" \
        --settings "$SETTINGS_FILE" \
        --permission-mode acceptEdits \
        --allowedTools "Bash,Read,Edit,Glob,Grep" \
        --continue \
        > "${REPORTS_DIR}/claude-implement-last.md"
    )
    ;;
  *)
    echo "未知 mode: $MODE" >&2
    usage
    ;;
esac

echo "[claude-pipeline] $MODE 完成，输出目录: $REPORTS_DIR"
