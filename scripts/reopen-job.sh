#!/usr/bin/env bash
# 兼容入口：登记缺陷 → 委托 report-bug.sh（bugs.md，非用户反馈）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
用法: reopen-job.sh <job-id> [--reason "描述"] [--by 来源]

等同于 report-bug.sh（写入 bugs.md → fix_needed）。
用户意见/建议请用 report-feedback.sh。

示例:
  reopen-job.sh job-20260530-103348 --reason "admin 注册路由 500" --by feishu-user
EOF
}

main() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  exec env PIPELINE_AGENT="${PIPELINE_AGENT:-agent-a}" "${SCRIPT_DIR}/report-bug.sh" "${args[@]}"
}

main "$@"
