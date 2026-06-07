#!/usr/bin/env bash
# agent-om 完成运维任务并写报告
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

TASK_ID="" PROJECT="" REPORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    -h|--help)
      echo "用法: om-task-complete.sh <task-id> --project <project> --report \"...\""
      exit 0
      ;;
    *)
      [[ -z "$TASK_ID" ]] && { TASK_ID="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

boundary_require_agent "agent-om,om-task-complete.sh" || exit 1

[[ -n "$TASK_ID" && -n "$PROJECT" && -n "$REPORT" ]] || {
  echo "用法: om-task-complete.sh <task-id> --project <project> --report \"...\"" >&2; exit 1
}

TASK_FILE="$(om_tasks_dir "$PROJECT")/${TASK_ID}.md"
[[ -f "$TASK_FILE" ]] || { echo "找不到任务: $TASK_FILE" >&2; exit 1; }

sed -i 's/^status: in_progress/status: done/' "$TASK_FILE"
REPORT_FILE="$(om_reports_dir "$PROJECT")/${TASK_ID}.md"
NOW="$(date -Iseconds)"

cat > "$REPORT_FILE" <<EOF
# 运维报告: ${TASK_ID}

- completedAt: ${NOW}
- agent: agent-om

${REPORT}
EOF

echo "报告: ${REPORT_FILE}"
