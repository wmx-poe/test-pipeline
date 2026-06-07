#!/usr/bin/env bash
# Claude Code 流水线封装（agent-coder / agent-verifier）
# 用法: claude-pipeline.sh <implement|verify|verify-fix|resume> <job-src-dir> "<prompt>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
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

case "$MODE" in
  implement|resume|verify-fix)
    require_pipeline_agents "claude-pipeline.sh" agent-coder manual
    ;;
  verify)
    require_pipeline_agents "claude-pipeline.sh" agent-verifier manual
    ;;
esac

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
    JOB_DIR="$(cd "$SRC_DIR/.." && pwd)"
    JOB_ID="$(basename "$JOB_DIR")"
    RUNTIME_EC=0
    if [[ -x "${SCRIPT_DIR}/verify-pipeline.sh" ]]; then
      "${SCRIPT_DIR}/verify-pipeline.sh" "$JOB_DIR" || RUNTIME_EC=$?
    else
      echo "警告: verify-pipeline.sh 不存在，跳过运行时验证" >&2
      RUNTIME_EC=2
    fi
    if [[ "$RUNTIME_EC" -ne 0 ]]; then
      echo "[claude-pipeline] 运行时验证失败，跳过 Claude 审查，自动回流 coder" >&2
      if [[ -x "${SCRIPT_DIR}/complete-verify.sh" ]]; then
        PIPELINE_VERIFY_CHAIN=1 PIPELINE_AGENT=agent-verifier \
          "${SCRIPT_DIR}/complete-verify.sh" "$JOB_ID" --runtime-only || true
      fi
      exit "${RUNTIME_EC:-1}"
    fi
    RUNTIME_NOTE="运行时验证通过（见 reports/verify-runtime.md）"
    FULL_PROMPT="${PROMPT}

---
【流水线强制要求】
1. 必须先阅读 ../reports/verify-runtime.md（及 deploy-info.md 若存在）
2. ${RUNTIME_NOTE}
3. 禁止仅做静态代码审查；结论必须综合运行时结果与 spec 验收标准
4. 在 reports/verify.md 末尾写「结论：PASS」或「结论：FAIL」
5. 若 FAIL，列出阻塞项清单供 coder 修复"
    PROMPT="$FULL_PROMPT"
    run_claude dontAsk "Bash,Read,Glob,Grep" "${REPORTS_DIR}/verify.md"
    if [[ -x "${SCRIPT_DIR}/complete-verify.sh" ]]; then
      PIPELINE_VERIFY_CHAIN=1 PIPELINE_AGENT=agent-verifier \
        "${SCRIPT_DIR}/complete-verify.sh" "$JOB_ID" --full || true
    fi
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
