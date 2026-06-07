#!/usr/bin/env bash
# 只读查询 job 进度（供 agent-a 飞书回复，禁止 docker/改代码）
# 用法: job-status.sh [job-id]  或  job-status.sh --latest [project]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "job-status.sh" agent-a manual

usage() {
  cat <<EOF
用法: job-status.sh <job-id>
      job-status.sh --latest [<project-slug>]

只读输出 status、verifyRound、最近 history、报告摘要路径。不跑 docker、不改文件。
EOF
}

summarize_job() {
  local job_id="$1"
  local job_dir
  job_dir="$(resolve_job_dir "$job_id")"
  local status_file="${job_dir}/status.json"
  [[ -f "$status_file" ]] || { echo "找不到 status: $status_file" >&2; exit 1; }

  python3 - <<PY
import json
from pathlib import Path

job_id = "${job_id}"
job_dir = Path("${job_dir}")
data = json.loads((job_dir / "status.json").read_text(encoding="utf-8"))
status = data.get("status", "?")
rnd = data.get("verifyRound", 0)
max_r = data.get("maxVerifyRounds", 10)
hist = data.get("history", [])[-3:]
reports = job_dir / "reports"
hints = []
for name in ("verify-user-report.md", "verify-feedback.md", "bugs.md", "user-feedback.md", "deploy-info.md"):
    p = reports / name
    if p.exists():
        hints.append(str(p))

print(f"job: {job_id}")
print(f"status: {status}")
print(f"verifyRound: {rnd}/{max_r}")
if hist:
    print("history (last 3):")
    for h in hist:
        print(f"  - {h.get('at','?')}: {h.get('from','?')} -> {h.get('to','?')} ({h.get('by','')}) {h.get('note','')}")
if hints:
    print("reports:")
    for h in hints:
        print(f"  - {h}")
PY
}

main() {
  local arg="${1:-}"
  if [[ -z "$arg" || "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "$arg" == "--latest" ]]; then
    local project="${2:-}"
    local job_id="" f jobdir
    if [[ -n "$project" ]]; then
      for f in "${WORKSPACE_ROOT}/${project}/jobs/"*/status.json; do
        [[ -f "$f" ]] || continue
        job_id="$(basename "$(dirname "$f")")"
      done
    else
      local latest_ts="" ts
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        ts="$(jq -r '.updatedAt // .createdAt // ""' "$f" 2>/dev/null || echo "")"
        if [[ -z "$latest_ts" || "$ts" > "$latest_ts" ]]; then
          latest_ts="$ts"
          jobdir="$(dirname "$f")"
          job_id="$(basename "$jobdir")"
        fi
      done < <(each_status_json)
    fi
    [[ -n "$job_id" ]] || { echo "未找到 job" >&2; exit 1; }
    summarize_job "$job_id"
    return
  fi

  summarize_job "$arg"
}

main "$@"
