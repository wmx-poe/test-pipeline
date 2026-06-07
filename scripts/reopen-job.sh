#!/usr/bin/env bash
# 将 inbox 反馈 / 交付后缺陷归并到原 job（不开新 job）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
load_env

JOB_ID="" REASON="" BY="${PIPELINE_AGENT:-reopen-job.sh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason) REASON="$2"; shift 2 ;;
    --by) BY="$2"; shift 2 ;;
    -h|--help)
      echo "用法: reopen-job.sh <job-id> --reason \"...\""
      exit 0
      ;;
    *)
      [[ -z "$JOB_ID" ]] && { JOB_ID="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

[[ -n "$JOB_ID" ]] || { echo "用法: reopen-job.sh <job-id> --reason \"...\"" >&2; exit 1; }
[[ -n "$REASON" ]] || REASON="用户反馈/Bug 归并"

"${SCRIPT_DIR}/report-bug.sh" "$JOB_ID" --reason "$REASON" --by "$BY"
echo "reopen-job: 已归并到原 job $JOB_ID（未创建新 job）"
