#!/usr/bin/env bash
# 运维任务目录与 ID 生成
set -euo pipefail

om_tasks_dir() {
  local project="$1"
  echo "${WORKSPACE_ROOT}/${project}/ops/tasks"
}

om_reports_dir() {
  local project="$1"
  echo "${WORKSPACE_ROOT}/${project}/ops/reports"
}

om_task_id() {
  echo "om-$(date +%Y%m%d-%H%M%S)-$$"
}

ensure_ops_layout() {
  local project="$1"
  mkdir -p "$(om_tasks_dir "$project")" "$(om_reports_dir "$project")"
}
