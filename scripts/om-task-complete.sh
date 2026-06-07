#!/usr/bin/env bash
# agent-om 完成任务 → reports/ + done/
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
# shellcheck source=lib/feishu-notify.sh
source "${SCRIPT_DIR}/lib/feishu-notify.sh"
load_env
require_pipeline_agents "om-task-complete.sh" agent-om manual

usage() {
  cat <<EOF
用法: om-task-complete.sh <project> <om-task-id> --status done|failed [--summary "一行摘要"]

从 stdin 或此处读取报告正文，写入 ops/reports/<id>.md，归档到 done/。
EOF
}

main() {
  local project="" task_id="" status="done" summary=""
  [[ $# -ge 2 ]] || { usage >&2; exit 1; }
  project="$1"
  task_id="$2"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --status) status="${2:-done}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done

  [[ "$status" == "done" || "$status" == "failed" ]] || {
    echo "--status 须为 done 或 failed" >&2
    exit 1
  }

  local ops running done_dir report_file
  ops="$(project_ops_dir "$project")"
  running="${ops}/running/${task_id}.md"
  done_dir="${ops}/done/${task_id}.md"
  report_file="${ops}/reports/${task_id}.md"
  [[ -f "$running" ]] || { echo "找不到 running 任务: $running" >&2; exit 1; }

  local now body
  now="$(date -Iseconds)"
  body="$(cat)"
  [[ -n "$body" ]] || body="${summary:-（无详细报告）}"

  cat > "$report_file" <<EOF
# 运维报告: ${task_id}

- **status**: ${status}
- **completedAt**: ${now}
- **summary**: ${summary:-（见下文）}

---

${body}
EOF

  sed -i "s/^status: running/status: ${status}/" "$running"
  mv "$running" "$done_dir"

  python3 - <<PY
import json
from pathlib import Path

ops = Path("${ops}")
task_id = "${task_id}"
status = "${status}"
now = "${now}"
report = "${report_file}"
status_path = ops / "status.json"
data = json.loads(status_path.read_text(encoding="utf-8"))
t = data.setdefault("tasks", {}).get(task_id)
if not t:
    raise SystemExit(f"status.json 无任务 {task_id}")
t["status"] = status
t["completedAt"] = now
t["report"] = report
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {task_id} -> {status}")
print(f"report: {report}")
PY

  feishu_notify_om_task "$project" "$task_id" "$status" "$summary" || true
}

main "$@"
