#!/usr/bin/env bash
# agent-a 取消运维任务
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "om-task-cancel.sh" agent-a manual

usage() {
  cat <<EOF
用法: om-task-cancel.sh <project> <om-task-id> [--reason "原因"]
EOF
}

main() {
  local project="${1:-}" task_id="${2:-}" reason=""
  [[ -n "$project" && -n "$task_id" ]] || { usage >&2; exit 1; }
  shift 2 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  local ops src done_file
  ops="$(project_ops_dir "$project")"
  if [[ -f "${ops}/inbox/${task_id}.md" ]]; then
    src="${ops}/inbox/${task_id}.md"
  elif [[ -f "${ops}/running/${task_id}.md" ]]; then
    src="${ops}/running/${task_id}.md"
  else
    echo "找不到可取消任务: $task_id" >&2
    exit 1
  fi

  local now
  now="$(date -Iseconds)"
  sed -i "s/^status: .*/status: cancelled/" "$src"
  done_file="${ops}/done/${task_id}.md"
  mv "$src" "$done_file"

  python3 - <<PY
import json
from pathlib import Path

ops = Path("${ops}")
task_id = "${task_id}"
now = "${now}"
reason = """${reason}"""
status_path = ops / "status.json"
data = json.loads(status_path.read_text(encoding="utf-8"))
t = data.setdefault("tasks", {}).get(task_id)
if t:
    t["status"] = "cancelled"
    t["completedAt"] = now
    if reason:
        t["cancelReason"] = reason
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {task_id} -> cancelled")
PY
}

main "$@"
