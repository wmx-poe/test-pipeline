#!/usr/bin/env bash
# agent-om 认领任务 pending → running
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
require_pipeline_agents "om-task-claim.sh" agent-om manual

usage() {
  cat <<EOF
用法: om-task-claim.sh <project> <om-task-id>
      om-task-claim.sh <project> --next

认领 inbox 中 pending 任务，移至 running/。
EOF
}

claim_one() {
  local project="$1" task_id="$2"
  local ops inbox running
  ops="$(project_ops_dir "$project")"
  inbox="${ops}/inbox/${task_id}.md"
  running="${ops}/running/${task_id}.md"
  [[ -f "$inbox" ]] || { echo "找不到 pending 任务: $inbox" >&2; exit 1; }

  local now
  now="$(date -Iseconds)"
  sed -i "s/^status: pending/status: running/" "$inbox"
  mv "$inbox" "$running"

  python3 - <<PY
import json
from pathlib import Path

status_path = Path("${ops}") / "status.json"
task_id = "${task_id}"
now = "${now}"
data = json.loads(status_path.read_text(encoding="utf-8"))
t = data.setdefault("tasks", {}).get(task_id)
if not t:
    raise SystemExit(f"status.json 无任务 {task_id}")
if t.get("status") != "pending":
    raise SystemExit(f"任务 {task_id} 非 pending: {t.get('status')}")
t["status"] = "running"
t["claimedAt"] = now
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {task_id} -> running")
print(f"task: {running}")
PY
}

main() {
  local project="${1:-}" arg2="${2:-}"
  [[ -n "$project" ]] || { usage >&2; exit 1; }

  if [[ "$arg2" == "--next" ]]; then
    local f task_id
    shopt -s nullglob
    for f in "$(project_ops_dir "$project")/inbox/"om-*.md; do
      task_id="$(basename "$f" .md)"
      claim_one "$project" "$task_id"
      return
    done
    echo "无 pending 运维任务" >&2
    exit 1
  fi

  [[ -n "$arg2" ]] || { usage >&2; exit 1; }
  claim_one "$project" "$arg2"
}

main "$@"
