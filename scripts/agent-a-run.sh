#!/usr/bin/env bash
# agent-a 唯一 exec 网关：仅允许白名单脚本，禁止 docker/systemctl 等系统操作
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "agent-a-run.sh" agent-a manual

usage() {
  cat <<EOF
用法: agent-a-run.sh <script-basename> [args...]

agent-a 飞书会话中 **唯一** 允许的 exec 入口。禁止直接 docker/systemctl/journalctl。

允许脚本:
  job-status.sh, new-job.sh, promote-job.sh, validate-spec.sh,
  report-bug.sh, report-feedback.sh, reopen-job.sh, continue-verify.sh,
  job-transition.sh,
  om-task-create.sh, om-task-list.sh, om-task-cancel.sh, deploy-servers-list.sh

示例:
  PIPELINE_AGENT=agent-a agent-a-run.sh job-status.sh --latest
  PIPELINE_AGENT=agent-a agent-a-run.sh om-task-create.sh proj-xxx --type logs --title "..."
EOF
}

ALLOWED=(
  job-status.sh
  new-job.sh
  promote-job.sh
  validate-spec.sh
  report-bug.sh
  report-feedback.sh
  reopen-job.sh
  continue-verify.sh
  job-transition.sh
  om-task-create.sh
  om-task-list.sh
  om-task-cancel.sh
  deploy-servers-list.sh
)

main() {
  local script="${1:-}"
  [[ -n "$script" ]] || { usage >&2; exit 1; }
  shift

  local base="${script##*/}"
  local allowed=0 s
  for s in "${ALLOWED[@]}"; do
    [[ "$base" == "$s" ]] && { allowed=1; break; }
  done
  if [[ "$allowed" -ne 1 ]]; then
    echo "agent-a 禁止执行: ${base}" >&2
    echo "请使用 agent-a-run.sh 白名单内脚本；系统运维请 om-task-create.sh 交给 agent-om" >&2
    exit 2
  fi

  local target="${SCRIPT_DIR}/${base}"
  [[ -x "$target" ]] || { echo "脚本不存在或不可执行: $target" >&2; exit 1; }
  exec env PIPELINE_AGENT=agent-a "$target" "$@"
}

main "$@"
