#!/usr/bin/env bash
# 用户反馈（非 Bug）→ reports/user-feedback.md，不触发 fix_needed
# 用法: report-feedback.sh <job-id> --reason "..." [--type suggestion|complaint|change|other] [--by feishu-user]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "report-feedback.sh" agent-a manual

usage() {
  cat <<EOF
用法: report-feedback.sh <job-id> --reason "描述" \\
  [--type suggestion|complaint|change|other] [--by 来源]

写入 reports/user-feedback.md。**不**改 status，**不**触发 agent-coder。
由 agent-a 分拣：新需求 / 改 spec / 确认后转 report-bug / 仅记录。

与 report-bug.sh 区别：
  - 反馈：意见、建议、体验抱怨、变更意向（未必是缺陷）
  - Bug：可复现、不符合验收标准的缺陷 → 用 report-bug.sh

示例:
  report-feedback.sh job-xxx --type suggestion --reason "希望导出 PDF" --by feishu-user
EOF
}

main() {
  local job_id="" reason="" ftype="other" by="feishu-user"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --type) ftype="${2:-other}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      *) job_id="$1"; shift ;;
    esac
  done

  [[ -n "$job_id" && -n "$reason" ]] || { usage >&2; exit 1; }

  local job_dir feedback_file now
  job_dir="$(resolve_job_dir "$job_id")"
  feedback_file="${job_dir}/reports/user-feedback.md"
  now="$(date -Iseconds)"
  mkdir -p "${job_dir}/reports"

  cat >> "$feedback_file" <<EOF

---

## ${now}（${by}）

**类型**: feedback / ${ftype}

${reason}

EOF

  echo "OK: feedback recorded (status unchanged)"
  echo "file: ${feedback_file}"
  log "用户反馈已登记: ${feedback_file}"
}

main "$@"
