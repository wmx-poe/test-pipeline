#!/usr/bin/env bash
# 同一 job 登记 Bug（不开新 job）→ fix_needed，由 timer 触发 coder
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

JOB_ID=""
REASON=""
BY="${PIPELINE_AGENT:-report-bug.sh}"
OM_TASK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason) REASON="$2"; shift 2 ;;
    --by) BY="$2"; shift 2 ;;
    --om-task) OM_TASK="$2"; shift 2 ;;
    -h|--help)
      echo "用法: report-bug.sh <job-id> --reason \"...\" [--by agent-a|agent-om] [--om-task <id>]"
      exit 0
      ;;
    *)
      [[ -z "$JOB_ID" ]] && { JOB_ID="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

[[ -n "$JOB_ID" && -n "$REASON" ]] || {
  echo "用法: report-bug.sh <job-id> --reason \"复现步骤...\"" >&2; exit 1
}

boundary_require_agent "agent-a,agent-om,report-bug.sh" || exit 1

JOB_DIR="$(resolve_job_dir "$JOB_ID")"
STATUS="${JOB_DIR}/status.json"
BUGS="${JOB_DIR}/reports/bugs.md"
repair_status_json "$STATUS"
mkdir -p "${JOB_DIR}/reports"

NOW="$(date -Iseconds)"
ENTRY="## Bug $(date +%Y%m%d-%H%M%S)
- by: ${BY}
- at: ${NOW}
${OM_TASK:+- om-task: ${OM_TASK}}
- reason: ${REASON}
"

if [[ -f "$BUGS" ]]; then
  echo "" >> "$BUGS"
  echo "$ENTRY" >> "$BUGS"
else
  cat > "$BUGS" <<EOF
# Bug 清单

${ENTRY}
EOF
fi

"${SCRIPT_DIR}/job-transition.sh" "$JOB_ID" --to fix_needed --by report-bug.sh \
  --note "Bug: ${REASON:0:120}"
echo "已登记 bugs.md 并设为 fix_needed，timer 将触发 agent-coder"
