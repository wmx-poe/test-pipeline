#!/usr/bin/env bash
# 手动创建任务（测试用）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env

TITLE="${1:-未命名任务}"
JOB_ID="job-$(date +%Y%m%d-%H%M%S)"
DEST="${PIPELINE_ROOT}/pipeline/jobs/${JOB_ID}"
mkdir -p "${DEST}/attachments" "${DEST}/design" "${DEST}/src" "${DEST}/reports"

cp "${PIPELINE_ROOT}/pipeline/jobs/_template/spec.md" "${DEST}/spec.md"
cp "${PIPELINE_ROOT}/pipeline/jobs/_template/status.json" "${DEST}/status.json"
sed -i "s/JOB_ID/${JOB_ID}/g; s/任务标题/${TITLE}/g" "${DEST}/status.json" "${DEST}/spec.md"
sed -i 's/"status": "draft"/"status": "pending"/' "${DEST}/status.json"
date -Iseconds | xargs -I{} sed -i "s/\"createdAt\": \"\"/\"createdAt\": \"{}\"/; s/\"updatedAt\": \"\"/\"updatedAt\": \"{}\"/" "${DEST}/status.json"

echo "已创建: ${DEST}"
echo "status=pending，等待 agent-design Cron 扫描"
