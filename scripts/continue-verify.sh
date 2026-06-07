#!/usr/bin/env bash
# 用户确认继续验证/修复：延长轮次上限并回流 coder
# 用法: continue-verify.sh <job-id> [--rounds 10] [--by feishu-user]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "continue-verify.sh" agent-a manual

usage() {
  cat <<EOF
用法: continue-verify.sh <job-id> [--rounds N] [--by 来源]

在 verify_paused（或 verify_failed）后，用户同意继续时：
- maxVerifyRounds += N（默认 10）
- status → fix_needed

示例:
  continue-verify.sh job-20260530-103348 --rounds 10 --by feishu-user
EOF
}

main() {
  local job_id="" rounds=10 by="continue-verify.sh"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --rounds) rounds="${2:-10}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      *) job_id="$1"; shift ;;
    esac
  done

  [[ -n "$job_id" ]] || { usage >&2; exit 1; }

  local job_dir
  job_dir="$(resolve_job_dir "$job_id")"
  local now
  now="$(date -Iseconds)"

  python3 - <<PY
import json
from pathlib import Path

job_dir = Path("${job_dir}")
status_path = job_dir / "status.json"
data = json.loads(status_path.read_text(encoding="utf-8"))
now = "${now}"
by = "${by}"
rounds = int("${rounds}")
current = data.get("status", "")
allowed = {"verify_paused", "verify_failed", "fix_needed"}
if current not in allowed:
    raise SystemExit(f"status={current}，仅 verify_paused/verify_failed/fix_needed 可 continue")

max_r = int(data.get("maxVerifyRounds", 10) or 10)
if max_r <= 0:
    max_r = 10
data["maxVerifyRounds"] = max_r + rounds

history = data.setdefault("history", [])
history.append({
    "at": now,
    "from": current,
    "to": "fix_needed",
    "by": by,
    "note": f"用户同意继续验证，maxVerifyRounds={data['maxVerifyRounds']}",
})
data["status"] = "fix_needed"
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

notified = job_dir / "reports" / ".verify-paused-notified"
if notified.exists():
    notified.unlink()
print(f"OK: ${job_id} -> fix_needed (maxVerifyRounds={data['maxVerifyRounds']})")
PY
}

main "$@"
