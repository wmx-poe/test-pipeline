#!/usr/bin/env bash
# 在已有 job 内登记 Bug/变更并回流 coder（禁止为此新建 job）
# 用法: reopen-job.sh <job-id> [--reason "描述"] [--by agent-a]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
load_env

usage() {
  cat <<EOF
用法: reopen-job.sh <job-id> [--reason "描述"] [--by 来源]

在已有任务内登记 Bug/未完成项，写入 reports/user-feedback.md，并将 status → fix_needed。
不创建新 job。draft/pending 阶段请直接更新原 job 的 spec.md。

示例:
  reopen-job.sh job-20260530-103348 --reason "admin 注册路由 500" --by feishu-user
EOF
}

main() {
  local job_id="" reason="" by="reopen-job.sh"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      *) job_id="$1"; shift ;;
    esac
  done

  [[ -n "$job_id" ]] || { usage >&2; exit 1; }

  local job_dir status_file feedback_file now
  job_dir="$(resolve_job_dir "$job_id")"
  status_file="${job_dir}/status.json"
  feedback_file="${job_dir}/reports/user-feedback.md"
  now="$(date -Iseconds)"
  mkdir -p "${job_dir}/reports"

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
        f"job 处于 {current}，请直接在原 job 更新 spec.md（新需求/analysis 阶段不开 reopen）"
    )
PY

  cat >> "$feedback_file" <<EOF

---

## ${now}（${by}）

${reason:-（未提供描述）}

EOF

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

if current != "fix_needed":
    entry = {
        "at": now,
        "from": current,
        "to": "fix_needed",
        "by": by,
        "note": (reason[:200] if reason else "user bug/change reopen"),
    }
    history.append(entry)

data["status"] = "fix_needed"
data["updatedAt"] = now
data.setdefault("verifyRound", 0)
data.setdefault("maxVerifyRounds", 10)
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: ${job_id} -> fix_needed")
PY
  rm -f "$REASON_FILE"

  log "已写入 ${feedback_file}"
}

main "$@"
