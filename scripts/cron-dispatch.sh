#!/usr/bin/env bash
# 有 pipeline 任务时才触发 OpenClaw Cron（不空跑 LLM）
# 由 systemd timer 或 crontab 每分钟调用；OpenClaw 内各 job 应保持 enabled=false
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
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

# OpenClaw cron 会话在跑（避免同一 agent 重复入队）
agent_cron_busy() {
  local agent_id="$1"
  pgrep -f "agent:${agent_id}:cron" >/dev/null 2>&1
}

# 遍历 workspace 内 status.json（通过 pipeline/jobs/*/job.md 索引）
# each_job_status / has_job_status 定义于 lib/job-paths.sh

# status=进行中 但缺少完成产物，且 agent / 子进程未在跑 → 卡死
# $1=status  $2=完成产物相对路径  $3=agentId  $4=可选子进程 busy 检测函数名
has_stuck_job() {
  local status="$1" artifact_rel="$2" agent_id="$3" sub_busy_fn="${4:-}"
  local jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    [[ -f "${jobdir}/${artifact_rel}" ]] && continue
    if agent_cron_busy "$agent_id"; then continue; fi
    if [[ -n "$sub_busy_fn" ]] && "$sub_busy_fn" "$jobdir"; then continue; fi
    return 0
  done < <(each_job_status "$status")
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

has_stuck_design_job() {
  has_stuck_job "designing" "design/DESIGN.md" "agent-design"
}

has_stuck_coder_job() {
  has_stuck_job "implementing" "reports/implement-summary.md" "agent-coder" coder_job_busy
}

has_stuck_verifier_job() {
  local jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    if agent_cron_busy "agent-verifier"; then continue; fi
    if verifier_job_busy "$jobdir"; then continue; fi
    # verifying 且 agent/子进程均未在跑 → 卡死（含已有 verify.md 但 status 未推进）
    return 0
  done < <(each_job_status "verifying")
  return 1
}

# 有 verifying 任务且 agent / claude 子进程正在跑（占 Docker 端口，阻塞并行 verify）
is_verifying_in_flight() {
  has_job_status verifying || return 1
  if agent_cron_busy "agent-verifier"; then return 0; fi
  local jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    if verifier_job_busy "$jobdir"; then return 0; fi
  done < <(each_job_status "verifying")
  return 1
}

# verified 但未复制到 project delivered/
has_stuck_verified_job() {
  local jobdir job_id delivered
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    job_id="$(basename "$jobdir")"
    delivered="$(delivered_dir_for_job "$job_id" 2>/dev/null || true)"
    [[ -n "$delivered" && -d "$delivered" ]] && continue
    if agent_cron_busy "agent-verifier"; then continue; fi
    return 0
  done < <(each_job_status "verified")
  return 1
}

should_run_design() {
  if has_job_status pending && ! has_job_status designing; then
    return 0
  fi
  has_stuck_design_job
}

should_run_coder() {
  if has_job_status fix_needed && ! has_job_status implementing; then
    return 0
  fi
  if has_job_status design_done && ! has_job_status implementing; then
    return 0
  fi
  has_stuck_coder_job
}

should_run_verify() {
  if has_stuck_verifier_job || has_stuck_verified_job; then
    return 0
  fi
  # impl_done 仅在无「进行中的 verify」时入队；verifying 但已空闲视为卡死（见上）
  if has_job_status impl_done && ! is_verifying_in_flight; then
    return 0
  fi
  return 1
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

has_unnotified_verify_paused() {
  local f jobdir
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    jq -e '.status == "verify_paused"' "$f" >/dev/null 2>&1 || continue
    jobdir="$(dirname "$f")"
    [[ -f "${jobdir}/reports/verify-user-report.md" ]] || continue
    [[ -f "${jobdir}/reports/.verify-paused-notified" ]] && continue
    return 0
  done < <(each_status_json)
  return 1
}

should_run_feedback() {
  has_feedback_sources || return 1
  ! agent_cron_busy "agent-feedback"
}

should_run_a_feedback() {
  has_unprocessed_inbox || has_unnotified_verify_paused || return 1
  ! agent_cron_busy "agent-a"
}

has_pending_ops_task() {
  local project_dir
  [[ -d "$WORKSPACE_ROOT" ]] || return 1
  for project_dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "$project_dir" ]] || continue
    compgen -G "${project_dir}/ops/inbox/om-"*.md >/dev/null 2>&1 && return 0
  done
  return 1
}

has_stuck_om_task() {
  local project_dir f
  [[ -d "$WORKSPACE_ROOT" ]] || return 1
  for project_dir in "$WORKSPACE_ROOT"/*; do
    [[ -d "${project_dir}/ops/running" ]] || continue
    for f in "${project_dir}/ops/running/"om-*.md; do
      [[ -f "$f" ]] || continue
      if agent_cron_busy "agent-om"; then continue; fi
      return 0
    done
  done
  return 1
}

should_run_om() {
  if has_pending_ops_task; then
    ! agent_cron_busy "agent-om" && return 0
  fi
  has_stuck_om_task
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
  if should_run_design; then
    if has_stuck_design_job; then
      vlog "条件满足: designing 卡死（无 design/DESIGN.md 且 agent-design 未在跑）"
    else
      vlog "条件满足: pending 且尚无 designing"
    fi
    trigger_job "pipeline-design-scan"
  else
    if has_job_status designing && agent_cron_busy "agent-design"; then
      vlog "跳过 design: agent-design 正在运行"
    else
      vlog "跳过 design: 无 pending / designing 未卡死"
    fi
  fi

  if should_run_coder; then
    if has_job_status fix_needed; then
      vlog "条件满足: fix_needed（验证失败待 coder 修复）"
    elif has_stuck_coder_job; then
      vlog "条件满足: implementing 卡死（无 implement-summary 且 claude 未在跑）"
    else
      vlog "条件满足: design_done 且尚无 implementing"
    fi
    trigger_job "pipeline-coder-scan"
  else
    if has_job_status implementing && agent_cron_busy "agent-coder"; then
      vlog "跳过 coder: agent-coder 正在运行"
    else
      vlog "跳过 coder"
    fi
  fi

  if should_run_verify; then
    if has_stuck_verified_job; then
      vlog "条件满足: verified 卡死（未登记 delivered 且 agent-verifier 未在跑）"
    elif has_stuck_verifier_job; then
      vlog "条件满足: verifying 卡死（agent/claude 未在跑，含 verify.md 已写但 status 未推进）"
    elif has_job_status impl_done; then
      vlog "条件满足: impl_done 且无进行中的 verify"
    fi
    trigger_job "pipeline-verify-scan"
  else
    if is_verifying_in_flight; then
      vlog "跳过 verify: 另有 verifying 任务进行中（agent 或 claude 在跑）"
    else
      vlog "跳过 verify"
    fi
  fi

  if should_run_feedback; then
    vlog "条件满足: delivered/raw 有待扫描内容且 agent-feedback 未在跑"
    trigger_job "pipeline-feedback-scan"
  else
    if has_feedback_sources && agent_cron_busy "agent-feedback"; then
      vlog "跳过 feedback-scan: agent-feedback 正在运行"
    else
      vlog "跳过 feedback-scan"
    fi
  fi

  if should_run_om; then
    if has_pending_ops_task; then
      vlog "条件满足: ops/inbox 有 pending 且 agent-om 未在跑"
    else
      vlog "条件满足: ops/running 卡死且 agent-om 未在跑"
    fi
    trigger_job "pipeline-om-scan"
  else
    if has_pending_ops_task && agent_cron_busy "agent-om"; then
      vlog "跳过 om-scan: agent-om 正在运行"
    else
      vlog "跳过 om-scan"
    fi
  fi

  if should_run_a_feedback; then
    if has_unnotified_verify_paused; then
      vlog "条件满足: verify_paused 待通知用户且 agent-a 未在跑"
    else
      vlog "条件满足: feedback/inbox 有未处理 md 且 agent-a 未在跑"
    fi
    trigger_job "pipeline-a-feedback-digest"
  else
    if ( has_unprocessed_inbox || has_unnotified_verify_paused ) && agent_cron_busy "agent-a"; then
      vlog "跳过 a-feedback-digest: agent-a 正在运行"
    else
      vlog "跳过 a-feedback-digest"
    fi
  fi
}

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "已有 dispatch 在运行，跳过"
  exit 0
fi

run_dispatch
