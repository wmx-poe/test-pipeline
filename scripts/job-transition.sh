#!/usr/bin/env bash
# 唯一合法的状态流转入口（timer / 白名单脚本）。OpenClaw Agent 禁止手改 status.json。
# 用法: job-transition.sh <job-id> --to <status> [--by <caller>] [--note "..."]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
load_env

usage() {
  cat <<EOF
用法: job-transition.sh <job-id> --to <status> [--by <caller>] [--note "..."]

合法流转由 timer（cron-dispatch）或白名单脚本调用。Agent 不得直接 edit status.json。

入口状态（仅 timer 可写）:
  pending→designing, design_done→implementing, fix_needed→implementing, impl_done→verifying

出口状态（各 Agent 经本脚本）:
  designing→design_done|design_failed, implementing→impl_done,
  verifying→verified|fix_needed|verify_paused（由 complete-verify.sh）
EOF
}

main() {
  local job_id="" to="" by="${PIPELINE_AGENT:-job-transition.sh}" note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to) to="$2"; shift 2 ;;
      --by) by="$2"; shift 2 ;;
      --note) note="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)
        [[ -z "$job_id" ]] && { job_id="$1"; shift; continue; }
        echo "未知参数: $1" >&2; usage >&2; exit 2
        ;;
    esac
  done

  [[ -n "$job_id" && -n "$to" ]] || { usage >&2; exit 2; }

  local job_dir status_file
  job_dir="$(resolve_job_dir "$job_id")"
  status_file="${job_dir}/status.json"
  repair_status_json "$status_file"

  local now frm
  now="$(date -Iseconds)"

  python3 - "$status_file" "$to" "$by" "$now" "$note" <<'PY'
import json, sys
from pathlib import Path

path, to, by, now, note = sys.argv[1:6]
data = json.loads(Path(path).read_text(encoding="utf-8"))
frm = data.get("status", "draft")

valid = {
    "draft", "pending", "designing", "design_done", "design_failed",
    "implementing", "impl_done", "verifying", "verified",
    "fix_needed", "verify_paused", "verify_failed", "delivered",
}
if to not in valid:
    raise SystemExit(f"非法 status: {to}")

# 允许规则（与 shell allowed_transition 对齐）
rules = {
    ("draft", "pending"): {"promote-job.sh"},
    ("pending", "designing"): {"cron-dispatch.sh"},
    ("designing", "design_done"): {"agent-design", "job-transition.sh"},
    ("designing", "design_failed"): {"agent-design", "job-transition.sh"},
    ("design_done", "implementing"): {"cron-dispatch.sh"},
    ("fix_needed", "implementing"): {"cron-dispatch.sh"},
    ("implementing", "impl_done"): {"agent-coder", "job-transition.sh"},
    ("impl_done", "verifying"): {"cron-dispatch.sh"},
    ("verifying", "verified"): {"complete-verify.sh"},
    ("verifying", "fix_needed"): {"complete-verify.sh", "report-bug.sh"},
    ("verifying", "verify_paused"): {"complete-verify.sh"},
    ("verifying", "verify_failed"): {"complete-verify.sh"},
    ("verify_paused", "impl_done"): {"continue-verify.sh"},
    ("verify_paused", "verifying"): {"continue-verify.sh"},
    ("fix_needed", "pending"): {"reopen-job.sh"},
    ("verified", "delivered"): {"agent-verifier"},
}
allowed = rules.get((frm, to))
if allowed is None and to == "fix_needed":
    allowed = {"report-bug.sh", "complete-verify.sh"}
if allowed is None or by not in allowed:
    if frm == to:
        print(f"OK: unchanged {frm}")
        raise SystemExit(0)
    raise SystemExit(f"拒绝流转 {frm}->{to} by={by}（仅 timer/白名单脚本可写）")

entry = {("pending", "designing"), ("design_done", "implementing"),
         ("fix_needed", "implementing"), ("impl_done", "verifying")}
if (frm, to) in entry and by != "cron-dispatch.sh":
    raise SystemExit(f"入口状态 {frm}->{to} 仅 cron-dispatch.sh（timer）可写")

entry = {"at": now, "from": frm, "to": to, "by": by}
if note:
    entry["note"] = note
data.setdefault("history", []).append(entry)
data["status"] = to
data["updatedAt"] = now
Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {data.get('id', '?')} {frm} -> {to} (by={by})")
PY
}

main "$@"
