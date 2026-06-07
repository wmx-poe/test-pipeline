#!/usr/bin/env bash
# 只读列出项目运维任务（agent-a 查结果 / 用户进度）
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
require_pipeline_agents "om-task-list.sh" agent-a agent-om manual

usage() {
  cat <<EOF
用法: om-task-list.sh <project> [--status pending|running|done|failed|cancelled|all]
EOF
}

main() {
  local project="${1:-}" filter="all"
  [[ -n "$project" ]] || { usage >&2; exit 1; }
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --status) filter="${2:-all}"; shift 2 ;;
      *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done

  local status_file
  status_file="$(ops_status_file "$project")"
  [[ -f "$status_file" ]] || { echo "无运维任务（ops/status.json 不存在）"; exit 0; }

  python3 - <<PY
import json
from pathlib import Path

status_path = Path("${status_file}")
filt = "${filter}"
data = json.loads(status_path.read_text(encoding="utf-8"))
tasks = data.get("tasks", {})
if not tasks:
    print("（无任务）")
    raise SystemExit(0)
rows = []
for tid, t in sorted(tasks.items(), key=lambda x: x[1].get("createdAt", ""), reverse=True):
    st = t.get("status", "?")
    if filt != "all" and st != filt:
        continue
    rows.append((tid, st, t.get("type", ""), t.get("title", ""), t.get("report")))
if not rows:
    print(f"（无 status={filt} 的任务）")
    raise SystemExit(0)
print(f"project: ${project}")
for tid, st, typ, title, report in rows:
    line = f"- {tid} [{st}] type={typ} {title}"
    if report:
        line += f" report={report}"
    print(line)
PY
}

main "$@"
