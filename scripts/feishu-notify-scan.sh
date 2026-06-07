#!/usr/bin/env bash
# 扫描工作区，对 agent 写入的 status 里程碑补发飞书（design_done / impl_done / verified / delivered）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/feishu-notify.sh
source "${SCRIPT_DIR}/lib/feishu-notify.sh"
load_env

scan_job() {
  local status_file="$1" job_dir status delivered

  job_dir="$(dirname "$status_file")"
  status="$(jq -r '.status // ""' "$status_file" 2>/dev/null || echo "")"

  case "$status" in
    design_done|impl_done|verified|verify_paused)
      feishu_notify_job_milestone "$job_dir" "$status" || true
      ;;
  esac

  delivered="$(delivered_dir_for_job "$(basename "$job_dir")" 2>/dev/null || true)"
  if [[ -n "$delivered" && -d "$delivered" ]]; then
    feishu_notify_job_milestone "$job_dir" "delivered" || true
  fi
}

main() {
  if ! feishu_notify_enabled; then
    exit 0
  fi

  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    scan_job "$f"
  done < <(each_status_json)
}

main "$@"
