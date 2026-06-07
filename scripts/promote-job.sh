#!/usr/bin/env bash
# 校验 spec 后将 status.json 从 draft 改为 pending（Agent A 或人工入队）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "promote-job.sh" agent-a manual

JOB_ID="${1:-}"
if [[ -z "$JOB_ID" ]]; then
  echo "用法: promote-job.sh <job-id>" >&2
  exit 1
fi

JOB_DIR="$(read_job_workspace "$JOB_ID")"
STATUS="${JOB_DIR}/status.json"

[[ -f "$STATUS" ]] || { echo "找不到 status.json: $STATUS" >&2; exit 1; }

"${SCRIPT_DIR}/validate-spec.sh" "$JOB_ID"

NOW="$(date -Iseconds)"
python3 - <<PY
import json
from pathlib import Path

status_path = Path("${STATUS}")
data = json.loads(status_path.read_text(encoding="utf-8"))
current = data.get("status", "")
if current not in ("draft", "pending"):
    raise SystemExit(f"当前 status={current!r}，仅 draft 可 promote 为 pending")

data["status"] = "pending"
data["updatedAt"] = "${NOW}"
history = data.setdefault("history", [])
if current == "draft":
    history.append({
        "at": "${NOW}",
        "from": "draft",
        "to": "pending",
        "by": "promote-job.sh",
    })
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"已入队: {data['id']} -> pending")
PY
