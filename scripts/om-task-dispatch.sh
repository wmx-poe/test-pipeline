#!/usr/bin/env bash
# agent-a 创建运维任务后直接唤起 agent-om（不经 timer / cron-dispatch）
# 用法: om-task-dispatch.sh <project> [<task-id>]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

require_cmd openclaw

PROJECT="${1:-}"
TASK_ID="${2:-}"
DRY_RUN="${DRY_RUN:-0}"

[[ -n "$PROJECT" ]] || {
  echo "用法: om-task-dispatch.sh <project> [<task-id>]" >&2
  exit 1
}

boundary_require_agent "agent-a,om-task-create.sh,om-task-dispatch.sh" || exit 1

TASK_FILE=""
if [[ -n "$TASK_ID" ]]; then
  TASK_FILE="$(om_tasks_dir "$PROJECT")/${TASK_ID}.md"
  [[ -f "$TASK_FILE" ]] || { echo "找不到任务: $TASK_FILE" >&2; exit 1; }
else
  for f in "$(om_tasks_dir "$PROJECT")"/om-*.md; do
    [[ -f "$f" ]] || continue
    grep -q '^status: pending' "$f" 2>/dev/null || continue
    TASK_FILE="$f"
    TASK_ID="$(basename "$f" .md)"
    break
  done
fi

[[ -n "$TASK_FILE" ]] || {
  echo "无 pending 运维任务: ${PROJECT}" >&2
  exit 1
}

MSG="【agent-a 下发】执行运维任务。
- project: ${PROJECT}
- task-id: ${TASK_ID}
- 任务文件: ${TASK_FILE}

请读取任务文件 frontmatter 与正文，按 type/server/jobId 执行：
1. om-task-claim.sh ${PROJECT}（若仍为 pending）
2. 执行 deploy/diagnose/logs
3. om-task-complete.sh ${TASK_ID} --project ${PROJECT} --report \"...\"
4. 若发现代码缺陷: report-bug.sh <job-id> --reason \"...\" --om-task ${TASK_ID}

本地验证 IP: ${PIPELINE_ROOT}/scripts/detect-pipeline-host-ip.sh
完成后只写 ops/reports/，不要飞书回复用户。"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "[dry-run] openclaw agent --agent agent-om --message \"...\""
  echo "task: ${TASK_FILE}"
  exit 0
fi

log "唤起 agent-om: ${TASK_ID} (${PROJECT})"
if ! openclaw agent --agent agent-om --message "$MSG" --no-deliver; then
  echo "警告: agent-om 唤起失败（见 openclaw logs）" >&2
  exit 1
fi
echo "已唤起 agent-om 执行任务 ${TASK_ID}"
