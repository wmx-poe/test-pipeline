#!/usr/bin/env bash
# 缺陷登记 → reports/bugs.md + status fix_needed（agent-a / agent-om / 人工）
# 用法: report-bug.sh <job-id> --reason "描述" [--by agent-a|agent-om|feishu-user] [--om-task om-xxx]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "report-bug.sh" agent-a agent-om manual

usage() {
  cat <<EOF
用法: report-bug.sh <job-id> --reason "描述" [--by 来源] [--om-task om-task-id]

写入 jobs/<job-id>/reports/bugs.md，并将 status → fix_needed。
用户意见/建议请用 report-feedback.sh → user-feedback.md（不触发 coder）。

agent-coder 在 fix_needed 时必读 bugs.md + verify-feedback.md。

来源示例:
  --by feishu-user     用户经 agent-a 飞书反馈
  --by agent-a         编排层登记
  --by agent-om        运维执行中发现代码/配置缺陷

示例:
  report-bug.sh job-20260530-103348 --reason "API 启动 MissingGreenlet" --by agent-om --om-task om-20260607-120000
EOF
}

main() {
  local job_id="" reason="" by="report-bug.sh" om_task=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      --om-task) om_task="${2:-}"; shift 2 ;;
      *) job_id="$1"; shift ;;
    esac
  done

  [[ -n "$job_id" ]] || { usage >&2; exit 1; }
  [[ -n "$reason" ]] || { echo "请提供 --reason" >&2; exit 1; }

  local job_dir status_file feedback_file now attribution
  job_dir="$(resolve_job_dir "$job_id")"
  status_file="${job_dir}/status.json"
  feedback_file="${job_dir}/reports/bugs.md"
  now="$(date -Iseconds)"
  mkdir -p "${job_dir}/reports"

  attribution="$by"
  [[ -n "$om_task" ]] && attribution="${by} | om-task: ${om_task}"

  python3 - <<PY
import json
from pathlib import Path

job_dir = Path("${job_dir}")
status_path = job_dir / "status.json"
data = json.loads(status_path.read_text(encoding="utf-8"))
current = data.get("status", "")
blocked = {"draft", "pending"}
if current in blocked:
    raise SystemExit(
        f"job 处于 {current}，Bug 请由 agent-a 更新 spec.md；或待入队后再 report-bug"
    )
PY

  local ops_ref=""
  if [[ -n "$om_task" ]]; then
    local project
    project="$(pointer_field "$(job_pointer "$job_id")" project 2>/dev/null || true)"
    if [[ -z "$project" ]]; then
      project="$(basename "$(dirname "$(dirname "$job_dir")")")"
    fi
    ops_ref="${WORKSPACE_ROOT}/${project}/ops/reports/${om_task}.md"
  fi

  cat >> "$feedback_file" <<EOF

---

## ${now}（${attribution}）

**类型**: bug

${reason}
EOF
  if [[ -n "$ops_ref" ]]; then
    cat >> "$feedback_file" <<EOF

**运维上下文**: \`${ops_ref}\`（agent-coder 修复前请阅读）
EOF
  fi
  echo "" >> "$feedback_file"

  REASON_FILE="$(mktemp)"
  printf '%s' "$reason" > "$REASON_FILE"

  python3 - <<PY
import json
from pathlib import Path

job_dir = Path("${job_dir}")
status_path = job_dir / "status.json"
reason_path = Path("${REASON_FILE}")
data = json.loads(status_path.read_text(encoding="utf-8"))
now = "${now}"
by = "${by}"
reason = reason_path.read_text(encoding="utf-8") if reason_path.exists() else ""
current = data.get("status", "")
history = data.setdefault("history", [])

note = f"bug report ({by})"
if reason:
    note = reason[:200]

if current != "fix_needed":
    history.append({
        "at": now,
        "from": current,
        "to": "fix_needed",
        "by": "report-bug.sh",
        "actor": by,
        "note": note,
    })

data["status"] = "fix_needed"
data["updatedAt"] = now
data.setdefault("verifyRound", data.get("verifyRound", 0))
data.setdefault("maxVerifyRounds", 10)
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: ${job_id} -> fix_needed (bug by {by})")
print(f"bugs: ${feedback_file}")
PY
  rm -f "$REASON_FILE"
  log "Bug 已登记: ${feedback_file}"
}

main "$@"
