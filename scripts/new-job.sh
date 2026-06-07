#!/usr/bin/env bash
# 手动创建任务（测试用）。默认 draft；仅 --pending 且 spec 校验通过才入队。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "new-job.sh" agent-a manual

TITLE="${1:-未命名任务}"
PENDING=0
if [[ "${1:-}" == "--pending" ]]; then
  PENDING=1
  TITLE="${2:-未命名任务}"
fi

JOB_ID="job-$(date +%Y%m%d-%H%M%S)"
CREATED_AT="$(date -Iseconds)"
BASE_SLUG="$(slugify_project "$TITLE" "$JOB_ID")"
PROJECT="$(unique_project_slug "$BASE_SLUG")"
WORKSPACE="$(project_root "$PROJECT")/jobs/${JOB_ID}"

ensure_project_layout "$PROJECT"
mkdir -p "${WORKSPACE}/attachments" "${WORKSPACE}/design" "${WORKSPACE}/src" "${WORKSPACE}/reports"

cp "${PIPELINE_ROOT}/pipeline/jobs/_template/spec.md" "${WORKSPACE}/spec.md"
cp "${PIPELINE_ROOT}/pipeline/jobs/_template/status.json" "${WORKSPACE}/status.json"
sed -i "s/JOB_ID/${JOB_ID}/g; s/PROJECT_SLUG/${PROJECT}/g; s/{{TITLE}}/${TITLE}/g; s/任务标题/${TITLE}/g" \
  "${WORKSPACE}/status.json" "${WORKSPACE}/spec.md"
sed -i "s/\"createdAt\": \"\"/\"createdAt\": \"${CREATED_AT}\"/; s/\"updatedAt\": \"\"/\"updatedAt\": \"${CREATED_AT}\"/" \
  "${WORKSPACE}/status.json"

write_job_pointer "$JOB_ID" "$PROJECT" "$TITLE" "$WORKSPACE" "$CREATED_AT"

if [[ "$PENDING" -eq 1 ]]; then
  "${SCRIPT_DIR}/promote-job.sh" "$JOB_ID"
else
  echo "已创建指针: $(job_pointer "$JOB_ID")"
  echo "工作区: ${WORKSPACE}"
  echo "status=draft — 请填写 spec.md 后执行: ${SCRIPT_DIR}/promote-job.sh ${JOB_ID}"
  echo "校验: ${SCRIPT_DIR}/validate-spec.sh ${JOB_ID}"
fi
