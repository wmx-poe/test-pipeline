#!/usr/bin/env bash
# 流水线调度中枢：systemd timer 每分钟调用；有任务才触发 OpenClaw Cron
# 入口 status 仅本脚本经 job-transition.sh 推进；OpenClaw Agent 禁止手改 status.json
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/status-integrity.sh
source "${SCRIPT_DIR}/lib/status-integrity.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
load_env

require_cmd openclaw
require_cmd jq

OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CRON_JSON="${OPENCLAW_HOME}/cron/jobs.json"
LOCK_FILE="${TMPDIR:-/tmp}/pipeline-cron-dispatch.lock"

VERBOSE="${VERBOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"

vlog() { if [[ "$VERBOSE" == 1 ]]; then log "$@"; fi; }

cron_job_id() {
  local name="$1"
  [[ -f "$CRON_JSON" ]] || return 1
  jq -r --arg n "$name" '.jobs[] | select(.name==$n) | .id' "$CRON_JSON" 2>/dev/null | head -1
}

agent_cron_busy() {
  local agent_id="$1"
  pgrep -f "agent:${agent_id}:cron" >/dev/null 2>&1
}

advance_entry_status() {
  local frm="$1" to="$2"
  local jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    local job_id
    job_id="$(basename "$jobdir")"
    if [[ "$DRY_RUN" == 1 ]]; then
      vlog "[dry-run] job-transition ${job_id} ${frm}->${to}"
    else
      PIPELINE_AGENT=cron-dispatch.sh "${SCRIPT_DIR}/job-transition.sh" "$job_id" \
        --to "$to" --by cron-dispatch.sh --note "timer entry" 2>/dev/null || true
    fi
  done < <(each_job_status_safe "$frm")
}

has_stuck_job() {
  local status="$1" artifact_rel="$2" agent_id="$3" sub_busy_fn="${4:-}"
  local jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    [[ -f "${jobdir}/${artifact_rel}" ]] && continue
    if agent_cron_busy "$agent_id"; then continue; fi
    if [[ -n "$sub_busy_fn" ]] && "$sub_busy_fn" "$jobdir"; then continue; fi
    return 0
  done < <(each_job_status_safe "$status")
  return 1
}

coder_job_busy() {
  local jobdir="$1"
  local src="${jobdir}/src"
  pgrep -f "claude-pipeline\\.sh (implement|resume).*${src}" >/dev/null 2>&1 \
    || pgrep -f "claude .*${src}" >/dev/null 2>&1
}

verifier_job_busy() {
  local jobdir="$1"
  local src="${jobdir}/src"
  pgrep -f "claude-pipeline\\.sh (verify|verify-fix).*${src}" >/dev/null 2>&1 \
    || pgrep -f "claude .*${src}" >/dev/null 2>&1
}

has_stuck_design_job() { has_stuck_job "designing" "design/DESIGN.md" "agent-design"; }
has_stuck_coder_job() { has_stuck_job "implementing" "reports/implement-summary.md" "agent-coder" coder_job_busy; }
has_stuck_verifier_job() { has_stuck_job "verifying" "reports/verify.md" "agent-verifier" verifier_job_busy; }

has_stuck_verified_job() {
  local jobdir job_id delivered
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    job_id="$(basename "$jobdir")"
    delivered="$(delivered_dir_for_job "$job_id" 2>/dev/null || true)"
    [[ -n "$delivered" && -d "$delivered" ]] && continue
    if agent_cron_busy "agent-verifier"; then continue; fi
    return 0
  done < <(each_job_status_safe "verified")
  return 1
}

should_run_design() {
  if has_job_status_safe pending && ! has_job_status_safe designing; then return 0; fi
  has_stuck_design_job
}

should_run_coder() {
  if has_job_status_safe fix_needed && ! has_job_status_safe implementing; then return 0; fi
  if has_job_status_safe design_done && ! has_job_status_safe implementing; then return 0; fi
  has_stuck_coder_job
}

should_run_verify() {
  if has_job_status_safe impl_done && ! has_job_status_safe verifying; then return 0; fi
  has_stuck_verifier_job || has_stuck_verified_job
}

has_pending_om_task() {
  local project_dir tasks
  [[ -d "$WORKSPACE_ROOT" ]] || return 1
  for project_dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "$project_dir" ]] || continue
    tasks="$(om_tasks_dir "$(basename "$project_dir")")"
    compgen -G "${tasks}/om-*.md" >/dev/null 2>&1 || continue
    grep -l '^status: pending' "${tasks}"/om-*.md >/dev/null 2>&1 && return 0
  done
  return 1
}

should_run_om() {
  has_pending_om_task || return 1
  ! agent_cron_busy "agent-om"
}

has_verify_paused_notify() {
  local jobdir flag
  while IFS= read -r jobdir; do
    flag="${jobdir}/reports/.verify-paused-notified"
    [[ -f "${jobdir}/reports/verify-user-report.md" ]] || continue
    [[ -f "$flag" ]] && continue
    return 0
  done < <(each_job_status_safe "verify_paused")
  return 1
}

should_run_a_verify_notify() {
  has_verify_paused_notify && ! agent_cron_busy "agent-a"
}

has_feedback_sources() {
  local project_dir
  [[ -d "$WORKSPACE_ROOT" ]] || return 1
  for project_dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "$project_dir" ]] || continue
    compgen -G "${project_dir}/delivered/*/status.json" >/dev/null 2>&1 && return 0
    compgen -G "${project_dir}/feedback/raw/"* >/dev/null 2>&1 && return 0
  done
  return 1
}

has_unprocessed_inbox() {
  local project_dir
  [[ -d "$WORKSPACE_ROOT" ]] || return 1
  for project_dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "$project_dir" ]] || continue
    compgen -G "${project_dir}/feedback/inbox/"*.md >/dev/null 2>&1 && return 0
  done
  return 1
}

should_run_feedback() {
  has_feedback_sources || return 1
  ! agent_cron_busy "agent-feedback"
}

should_run_a_feedback() {
  has_unprocessed_inbox || return 1
  ! agent_cron_busy "agent-a"
}

trigger_job() {
  local name="$1"
  local id
  id="$(cron_job_id "$name")"
  if [[ -z "$id" || "$id" == null ]]; then
    log "跳过 $name：未在 ${CRON_JSON} 中找到（先运行 ./scripts/setup-cron.sh）"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    log "[dry-run] openclaw cron run $id  # $name"
    return 0
  fi
  log "触发 $name ($id)"
  if ! openclaw cron run "$id"; then
    log "警告: $name 运行失败（见 openclaw logs）"
  fi
}

run_dispatch() {
  # timer 推进入口 status（Agent 禁止手改）
  if should_run_design; then
    advance_entry_status pending designing
    trigger_job "pipeline-design-scan"
  else
    vlog "跳过 design"
  fi

  if should_run_coder; then
    advance_entry_status design_done implementing
    advance_entry_status fix_needed implementing
    trigger_job "pipeline-coder-scan"
  else
    vlog "跳过 coder"
  fi

  if should_run_verify; then
    advance_entry_status impl_done verifying
    trigger_job "pipeline-verify-scan"
  else
    vlog "跳过 verify"
  fi

  if should_run_om; then
    vlog "条件满足: 有 pending 运维任务"
    trigger_job "pipeline-om-scan"
  else
    vlog "跳过 om"
  fi

  if should_run_a_verify_notify; then
    vlog "条件满足: verify_paused 待通知用户"
    trigger_job "pipeline-a-verify-notify"
  fi

  if should_run_feedback; then
    trigger_job "pipeline-feedback-scan"
  else
    vlog "跳过 feedback-scan"
  fi

  if should_run_a_feedback; then
    trigger_job "pipeline-a-feedback-digest"
  else
    vlog "跳过 a-feedback-digest"
  fi
}

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "已有 dispatch 在运行，跳过"
  exit 0
fi

run_dispatch
