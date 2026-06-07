#!/usr/bin/env bash
# 只读查看 job 状态（含容错修复后的 status.json）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
load_env

show_job() {
  local job_id="$1"
  local job_dir status_file
  job_dir="$(resolve_job_dir "$job_id")"
  status_file="${job_dir}/status.json"
  repair_status_json "$status_file"
  echo "=== ${job_id} ==="
  echo "workspace: ${job_dir}"
  jq -r '"status: \(.status) | verifyRound: \(.verifyRound // 0)/\(.maxVerifyRounds // 10) | iteration: \(.verifyIteration // 0)"' "$status_file"
  local r
  for r in implement-summary.md verify-runtime.md verify.md verify-feedback.md bugs.md deploy-info.md; do
    [[ -f "${job_dir}/reports/${r}" ]] && echo "  reports/${r}: yes" || true
  done
  echo ""
}

if [[ "${1:-}" == "--latest" ]]; then
  latest=""
  while IFS= read -r f; do
    latest="$f"
  done < <(each_status_json_safe | sort -r | head -5)
  if [[ -z "$latest" ]]; then
    echo "无任务"
    exit 0
  fi
  show_job "$(basename "$(dirname "$latest")")"
  exit 0
fi

[[ -n "${1:-}" ]] || { echo "用法: job-status.sh <job-id> | --latest" >&2; exit 1; }
show_job "$1"
