#!/usr/bin/env bash
# 验证暂停后用户确认进入下一轮迭代
# 用法: continue-verify.sh <job-id> [--rounds N] [--by feishu-user]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
load_env

JOB_ID="${1:-}"
ROUNDS=10
BY="${PIPELINE_AGENT:-continue-verify.sh}"

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rounds) ROUNDS="$2"; shift 2 ;;
    --by) BY="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$JOB_ID" ]] || { echo "用法: continue-verify.sh <job-id> [--rounds 10] [--by feishu-user]" >&2; exit 1; }

JOB_DIR="$(resolve_job_dir "$JOB_ID")"
STATUS="${JOB_DIR}/status.json"
repair_status_json "$STATUS"

NOW="$(date -Iseconds)"
python3 - "$STATUS" "$ROUNDS" "$BY" "$NOW" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
rounds = int(sys.argv[2])
by = sys.argv[3]
now = sys.argv[4]
data = json.loads(path.read_text(encoding="utf-8"))
cur = data.get("status")
if cur not in ("verify_paused", "verify_failed"):
    raise SystemExit(f"当前 status={cur!r}，仅 verify_paused/verify_failed 可 continue")

data["verifyRound"] = 0
data["verifyIteration"] = int(data.get("verifyIteration", 0)) + 1
data["maxVerifyRounds"] = rounds
data["status"] = "impl_done"
data["updatedAt"] = now
data.setdefault("history", []).append({
    "at": now, "from": cur, "to": "impl_done", "by": by,
    "note": f"用户确认进入第 {data['verifyIteration']} 轮验证（每轮最多 {rounds} 次）",
})
# 清除暂停通知标记
flag = path.parent / "reports" / ".verify-paused-notified"
if flag.exists():
    flag.unlink()
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {data['id']} -> impl_done (iteration={data['verifyIteration']}, maxRounds={rounds})")
PY

echo "下一轮验证将由 timer 自动触发 pipeline-verify-scan"
