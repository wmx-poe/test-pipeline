#!/usr/bin/env bash
# 取消 pending 运维任务（agent-a）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

TASK_ID="" PROJECT="" REASON="用户取消"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    -h|--help)
      echo "用法: om-task-cancel.sh <task-id> --project <project> [--reason \"...\"]"
      exit 0
      ;;
    *)
      [[ -z "$TASK_ID" ]] && { TASK_ID="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

boundary_require_agent "agent-a,om-task-cancel.sh" || exit 1

[[ -n "$TASK_ID" && -n "$PROJECT" ]] || {
  echo "用法: om-task-cancel.sh <task-id> --project <project>" >&2; exit 1
}

TASK_FILE="$(om_tasks_dir "$PROJECT")/${TASK_ID}.md"
[[ -f "$TASK_FILE" ]] || { echo "找不到任务: $TASK_FILE" >&2; exit 1; }

if grep -q '^status: in_progress' "$TASK_FILE"; then
  echo "任务进行中，无法取消" >&2
  exit 1
fi

sed -i 's/^status: pending/status: cancelled/' "$TASK_FILE"
echo "- cancelledAt: $(date -Iseconds)" >> "$TASK_FILE"
echo "- cancelReason: ${REASON}" >> "$TASK_FILE"
echo "已取消: ${TASK_ID}"
