#!/usr/bin/env bash
# 创建运维任务（agent-a 下发，agent-om 执行）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env

PROJECT="" TYPE="" TITLE="" BODY="" JOB_ID="" SERVER="" BY="${PIPELINE_AGENT:-agent-a}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --job-id) JOB_ID="$2"; shift 2 ;;
    --server) SERVER="$2"; shift 2 ;;
    --by) BY="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
用法: om-task-create.sh <project> --type deploy|diagnose|logs|other \\
  --title "..." [--body "..."] [--job-id <id>] [--server local|prod]

部署（--type deploy）必须 --server；生产服务器在 config/.env。
EOF
      exit 0
      ;;
    *)
      [[ -z "$PROJECT" ]] && { PROJECT="$1"; shift; continue; }
      echo "未知参数: $1" >&2; exit 2
      ;;
  esac
done

boundary_require_agent "agent-a,om-task-create.sh" || exit 1

[[ -n "$PROJECT" && -n "$TYPE" && -n "$TITLE" ]] || {
  echo "用法: om-task-create.sh <project> --type ... --title ..." >&2; exit 1
}

if [[ "$TYPE" == "deploy" && -z "$SERVER" ]]; then
  echo "部署任务必须指定 --server（先运行 deploy-servers-list.sh 让用户选择）" >&2
  exit 1
fi

ensure_ops_layout "$PROJECT"
TASK_ID="$(om_task_id)"
NOW="$(date -Iseconds)"
TASK_FILE="$(om_tasks_dir "$PROJECT")/${TASK_ID}.md"

cat > "$TASK_FILE" <<EOF
---
id: ${TASK_ID}
project: ${PROJECT}
type: ${TYPE}
status: pending
server: ${SERVER:-}
jobId: ${JOB_ID:-}
createdAt: "${NOW}"
createdBy: ${BY}
title: "${TITLE}"
---

# ${TITLE}

${BODY:-（无详细说明）}

## 执行要求

- 类型: ${TYPE}
${SERVER:+ - 目标服务器: ${SERVER}}
${JOB_ID:+ - 关联 job: ${JOB_ID}}
- 完成后运行: om-task-complete.sh ${TASK_ID} --project ${PROJECT} --report "..."
- 若发现代码缺陷: report-bug.sh <job-id> --reason "..." --om-task ${TASK_ID}
EOF

echo "已创建运维任务: ${TASK_ID}"
echo "路径: ${TASK_FILE}"
echo "agent-om 将由 timer pipeline-om-scan 认领执行"
