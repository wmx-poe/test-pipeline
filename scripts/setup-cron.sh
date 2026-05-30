#!/usr/bin/env bash
# 注册 OpenClaw 每分钟（及反馈 Agent 每 5 分钟）的 Cron 任务
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env
require_cmd openclaw

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      echo "用法: $0 [--force]"
      echo "  --force  删除并重建 pipeline-coder-scan / pipeline-verify-scan"
      exit 0
      ;;
  esac
done

SCAN_DESIGN='扫描 pipeline/jobs 下 status.json 为 pending 的任务：更新为 designing，读 spec.md，用 Stitch MCP 产出到 design/，完成后 status=design_done。无任务则 NO_REPLY。'
SCAN_CODER="扫描 status=design_done：更新 implementing，在任务 src/ 目录用 ${PIPELINE_ROOT}/scripts/claude-pipeline.sh implement 实现，写 reports/implement-summary.md，status=impl_done。无任务则 NO_REPLY。"
SCAN_VERIFY="扫描 status=impl_done：更新 verifying，用 ${PIPELINE_ROOT}/scripts/claude-pipeline.sh verify 对照 spec 验证，写 reports/verify.md（结论 PASS/FAIL），PASS 则 verified 并登记 delivered。无任务则 NO_REPLY。"
SCAN_FEEDBACK='扫描 pipeline/delivered 与 pipeline/feedback/raw，生成 pipeline/feedback/inbox/*.md（feature_request/bug_report/user_complaint）。无新内容则 NO_REPLY。'
SCAN_A_FEEDBACK='读取 pipeline/feedback/inbox 下未处理 md，向用户摘要；高优先级可建议新建任务。无新反馈则 NO_REPLY。'

remove_job_if_force() {
  local name="$1"
  if [[ "$FORCE" -eq 1 ]] && openclaw cron list 2>/dev/null | grep -qF "$name"; then
    local job_id
    job_id="$(openclaw cron list 2>/dev/null | awk -v n="$name" '$0 ~ n {print $1; exit}')"
    if [[ -n "$job_id" ]]; then
      openclaw cron remove "$job_id" 2>/dev/null || true
      log "已删除 Cron: $name ($job_id)"
    fi
  fi
}

add_job() {
  local name="$1" agent="$2" cron_expr="$3" msg="$4"
  remove_job_if_force "$name"
  if openclaw cron list 2>/dev/null | grep -qF "$name"; then
    log "Cron 已存在，跳过: $name"
    return 0
  fi
  openclaw cron add \
    --name "$name" \
    --cron "$cron_expr" \
    --session isolated \
    --agent "$agent" \
    --message "$msg" \
    --no-deliver \
    --light-context
  log "已创建 Cron: $name → agent=$agent"
}

log "注册流水线 Cron 任务..."
add_job "pipeline-design-scan" "agent-design" "* * * * *" "$SCAN_DESIGN"
add_job "pipeline-coder-scan" "agent-coder" "* * * * *" "$SCAN_CODER"
add_job "pipeline-verify-scan" "agent-verifier" "* * * * *" "$SCAN_VERIFY"
add_job "pipeline-feedback-scan" "agent-feedback" "*/5 * * * *" "$SCAN_FEEDBACK"
add_job "pipeline-a-feedback-digest" "agent-a" "*/5 * * * *" "$SCAN_A_FEEDBACK"

openclaw cron list
log "完成。确保 Gateway 运行: openclaw gateway status"
