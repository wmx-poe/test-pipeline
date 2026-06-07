#!/usr/bin/env bash
# 流水线 status 唯一变更入口（除 promote/report-bug/complete-verify 等专用脚本外）。
# 入口状态（pending→designing 等）仅 cron-dispatch 可写；出口状态由各 Agent 经本脚本提交。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

usage() {
  cat <<EOF
用法: job-transition.sh <job-id> --to <status> [--note "说明"]

状态变更须经本脚本（禁止 Agent 手 edit status.json）。
入口推进（designing/implementing/verifying）仅 cron-dispatch 调用（PIPELINE_DISPATCH=1）。

出口示例（Agent cron 会话内）:
  PIPELINE_AGENT=agent-design job-transition.sh <job-id> --to design_done
  PIPELINE_AGENT=agent-coder   job-transition.sh <job-id> --to impl_done
EOF
}

JOB_ID="${1:-}"
TO_STATUS=""
NOTE=""
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TO_STATUS="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$JOB_ID" && -n "$TO_STATUS" ]] || { usage >&2; exit 1; }

JOB_DIR="$(read_job_workspace "$JOB_ID")"
STATUS_FILE="${JOB_DIR}/status.json"
[[ -f "$STATUS_FILE" ]] || { echo "找不到 status.json: $STATUS_FILE" >&2; exit 1; }

# dispatch 入口由 PIPELINE_DISPATCH=1 授权；出口由对应 Agent 或 manual 调用
if [[ "${PIPELINE_DISPATCH:-0}" != "1" ]]; then
  require_pipeline_agents "job-transition.sh" \
    agent-design agent-coder agent-a manual
fi

AGENT="$(pipeline_resolve_agent)"
DISPATCH="${PIPELINE_DISPATCH:-0}"
NOW="$(date -Iseconds)"

python3 - <<PY
import json
import os
import sys
from pathlib import Path

job_id = "${JOB_ID}"
to_status = "${TO_STATUS}"
note = """${NOTE}"""
now = "${NOW}"
agent = """${AGENT}"""
dispatch = """${DISPATCH}"""

status_path = Path("${STATUS_FILE}")
data = json.loads(status_path.read_text(encoding="utf-8"))
current = data.get("status", "")
history = data.setdefault("history", [])

# (from_status, to_status) -> allowed callers
# caller: "dispatch" | agent-id | "manual" | script name patterns
TRANSITIONS = {
    ("pending", "designing"): {"dispatch"},
    ("designing", "design_done"): {"agent-design"},
    ("designing", "design_failed"): {"agent-design"},
    ("design_done", "implementing"): {"dispatch"},
    ("fix_needed", "implementing"): {"dispatch"},
    ("implementing", "impl_done"): {"agent-coder"},
    ("impl_done", "verifying"): {"dispatch"},
    ("verify_paused", "verify_failed"): {"agent-a", "manual"},
    ("verify_failed", "fix_needed"): {"continue-verify.sh", "agent-a", "manual"},
}

key = (current, to_status)
allowed = TRANSITIONS.get(key)
if allowed is None:
    raise SystemExit(
        f"非法迁移: {current!r} -> {to_status!r}（须经 promote-job/report-bug/complete-verify 等专用脚本）"
    )

def caller_ok() -> bool:
    if "dispatch" in allowed and dispatch == "1":
        return True
    if agent in allowed:
        return True
    if agent == "manual" and "manual" in allowed:
        return True
    # complete-verify / continue-verify 经 PIPELINE_AGENT 或脚本名推断
    if agent in ("agent-verifier", "verify-chain") and to_status in (
        "verified", "fix_needed", "verify_paused", "verify_failed"
    ):
        return False  # 须走 complete-verify.sh
    return False

if not caller_ok():
    raise SystemExit(
        f"边界拒绝: {current}->{to_status} 不允许由 agent={agent!r} dispatch={dispatch} 调用\n"
        f"  入口状态仅 cron-dispatch（PIPELINE_DISPATCH=1）可推进\n"
        f"  人工: PIPELINE_AGENT=manual job-transition.sh ..."
    )

# 产物门禁（出口）
job_dir = status_path.parent
if to_status == "design_done" and not (job_dir / "design" / "DESIGN.md").is_file():
    raise SystemExit("缺少 design/DESIGN.md，不能设为 design_done")
if to_status == "impl_done" and not (job_dir / "reports" / "implement-summary.md").is_file():
    raise SystemExit("缺少 reports/implement-summary.md，不能设为 impl_done")

by = "job-transition.sh"
if dispatch == "1":
    by = "cron-dispatch.sh"

entry = {"at": now, "from": current, "to": to_status, "by": by, "agent": agent}
if note:
    entry["note"] = note
history.append(entry)

data["status"] = to_status
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {job_id} {current} -> {to_status} (by={by}, agent={agent})")
PY
