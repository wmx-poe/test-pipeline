#!/usr/bin/env bash
# 用户反馈（建议/抱怨），不自动触发 coder
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

JOB_ID="" TYPE="suggestion" REASON="" BY="${PIPELINE_AGENT:-report-feedback.sh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    --by) BY="$2"; shift 2 ;;
    -h|--help)
      echo "用法: report-feedback.sh <job-id> --type suggestion|complaint|other --reason \"...\""
      exit 0
      ;;
    *)
      [[ -z "$JOB_ID" ]] && { JOB_ID="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

[[ -n "$JOB_ID" && -n "$REASON" ]] || {
  echo "用法: report-feedback.sh <job-id> --type ... --reason \"...\"" >&2; exit 1
}

boundary_require_agent "agent-a,report-feedback.sh" || exit 1

JOB_DIR="$(resolve_job_dir "$JOB_ID")"
FB="${JOB_DIR}/reports/user-feedback.md"
mkdir -p "${JOB_DIR}/reports"
NOW="$(date -Iseconds)"

if [[ ! -f "$FB" ]]; then
  echo "# 用户反馈" > "$FB"
fi
cat >> "$FB" <<EOF

## ${TYPE} $(date +%Y%m%d-%H%M%S)
- by: ${BY}
- at: ${NOW}
- content: ${REASON}
EOF
echo "已写入 user-feedback.md（不自动改 status）"
