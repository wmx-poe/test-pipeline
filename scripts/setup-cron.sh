#!/usr/bin/env bash
# 注册 OpenClaw Cron 任务（默认 disabled，由 cron-dispatch.sh 按任务状态触发）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env
require_cmd openclaw
require_cmd jq

OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CRON_JSON="${OPENCLAW_HOME}/cron/jobs.json"

FORCE=0
INSTALL_TIMER=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --install-timer) INSTALL_TIMER=1 ;;
    -h|--help)
      cat <<EOF
用法: $0 [--force] [--install-timer]

注册流水线 OpenClaw Cron 定义（enabled=false，不按时空跑）。
实际触发由 scripts/cron-dispatch.sh 根据 pipeline/jobs/*/job.md 索引的工作区状态自动执行。

  --force           删除同名 job 后重建
  --install-timer   安装用户级 systemd timer（每分钟 dispatch）

日常：
  ./scripts/setup-cron.sh --install-timer   # 首次
  ./scripts/cron-dispatch.sh --dry-run      # 需设置 DRY_RUN=1，见脚本 VERBOSE
  VERBOSE=1 ./scripts/cron-dispatch.sh      # 查看跳过原因
EOF
      exit 0
      ;;
  esac
done

SCAN_DESIGN="【禁止手改 status.json】入口 pending→designing 已由 timer 完成。扫描 pending/designing 卡死：validate-spec → Stitch → design/ → job-transition --to design_done。无任务 NO_REPLY。"
SCAN_CODER="【禁止手改 status.json】入口 design_done/fix_needed→implementing 已由 timer 完成。读 spec/design 或 verify-feedback/bugs.md → claude-pipeline implement|resume → job-transition --to impl_done。无任务 NO_REPLY。"
SCAN_VERIFY="【禁止手改 status.json】入口 impl_done→verifying 已由 timer 完成。verify-pipeline（本机 IP 探活）→ claude-pipeline verify → complete-verify 自动设 verified/fix_needed/verify_paused。verified 补 delivered。无任务 NO_REPLY。"
SCAN_OM="【agent-om 专用】扫描 ${WORKSPACE_ROOT}/*/ops/tasks/ 中 status=pending 的任务；claim → 执行 deploy/diagnose/logs（deploy 须 task 内 server 字段）；写 ops/reports/；发现代码 Bug 用 report-bug.sh --om-task。本地验证 IP 见 detect-pipeline-host-ip.sh。无任务 NO_REPLY。"
SCAN_FEEDBACK="扫描 ${WORKSPACE_ROOT}/*/delivered 与 */feedback/raw，生成 */feedback/inbox/*.md。Bug 建议 reopen 原 job，非新 job。无新内容 NO_REPLY。"
SCAN_A_FEEDBACK="读取 ${WORKSPACE_ROOT}/*/feedback/inbox 未处理 md，摘要给用户；bug→reopen-job；新功能→确认后 new-job。无新反馈 NO_REPLY。"
SCAN_A_VERIFY="扫描 status=verify_paused 且未通知的任务：读 verify-user-report.md，飞书通知用户是否继续下一轮（continue-verify.sh）。通知后 touch reports/.verify-paused-notified。无任务 NO_REPLY。"

# 占位 schedule（job 为 disabled，不由 OpenClaw 定时触发）
PLACEHOLDER_CRON="0 0 1 1 *"
MODEL_PRO="${OPENCLAW_CRON_MODEL_PRO:-deepseek/deepseek-v4-pro[1m]}"
MODEL_FLASH="${OPENCLAW_CRON_MODEL_FLASH:-deepseek/deepseek-v4-flash}"

cron_job_exists() {
  local name="$1"
  [[ -f "$CRON_JSON" ]] || return 1
  jq -e --arg n "$name" '.jobs[] | select(.name==$n)' "$CRON_JSON" >/dev/null 2>&1
}

dedupe_cron_by_name() {
  local name="$1"
  [[ -f "$CRON_JSON" ]] || return 0
  mapfile -t ids < <(jq -r --arg n "$name" '.jobs[] | select(.name==$n) | .id' "$CRON_JSON")
  if [[ ${#ids[@]} -le 1 ]]; then
    return 0
  fi
  local id
  for id in "${ids[@]:1}"; do
    log "删除重复 Cron: $name ($id)"
    openclaw cron remove "$id" 2>/dev/null || true
  done
}

remove_job_if_force() {
  local name="$1"
  [[ "$FORCE" -eq 1 ]] || return 0
  [[ -f "$CRON_JSON" ]] || return 0
  mapfile -t ids < <(jq -r --arg n "$name" '.jobs[] | select(.name==$n) | .id' "$CRON_JSON")
  local id
  for id in "${ids[@]}"; do
    [[ -n "$id" && "$id" != null ]] || continue
    openclaw cron remove "$id" 2>/dev/null || true
    log "已删除 Cron: $name ($id)"
  done
}

add_job() {
  local name="$1" agent="$2" msg="$3" model="${4:-}"
  remove_job_if_force "$name"
  dedupe_cron_by_name "$name"
  if cron_job_exists "$name"; then
    log "Cron 已存在，跳过: $name"
    return 0
  fi
  local -a args=(
    add
    --name "$name"
    --cron "$PLACEHOLDER_CRON"
    --session isolated
    --agent "$agent"
    --message "$msg"
    --no-deliver
    --light-context
    --disabled
  )
  if [[ -n "$model" ]]; then
    args+=(--model "$model")
  fi
  openclaw cron "${args[@]}"
  log "已创建 Cron（disabled）: $name → agent=$agent model=${model:-default}"
}

install_dispatch_timer() {
  local svc_src="${REPO_ROOT}/config/systemd/pipeline-cron-dispatch.service"
  local tmr_src="${REPO_ROOT}/config/systemd/pipeline-cron-dispatch.timer"
  local svc_dst="${HOME}/.config/systemd/user/pipeline-cron-dispatch.service"
  local tmr_dst="${HOME}/.config/systemd/user/pipeline-cron-dispatch.timer"
  mkdir -p "${HOME}/.config/systemd/user"
  # 按 PIPELINE_ROOT 写入 EnvironmentFile 路径
  sed "s|%h/workspace/test-pipeline|${PIPELINE_ROOT}|g" "$svc_src" > "$svc_dst"
  sed "s|%h/workspace/test-pipeline|${PIPELINE_ROOT}|g" "$tmr_src" > "$tmr_dst"
  systemctl --user daemon-reload
  systemctl --user enable --now pipeline-cron-dispatch.timer
  log "已安装并启动 pipeline-cron-dispatch.timer"
  systemctl --user status pipeline-cron-dispatch.timer --no-pager || true
}

log "注册流水线 Cron（disabled + dispatch 触发）..."
add_job "pipeline-design-scan" "agent-design" "$SCAN_DESIGN" "$MODEL_PRO"
add_job "pipeline-coder-scan" "agent-coder" "$SCAN_CODER" "$MODEL_FLASH"
add_job "pipeline-verify-scan" "agent-verifier" "$SCAN_VERIFY" "$MODEL_FLASH"
add_job "pipeline-om-scan" "agent-om" "$SCAN_OM" "$MODEL_FLASH"
add_job "pipeline-feedback-scan" "agent-feedback" "$SCAN_FEEDBACK" "$MODEL_FLASH"
add_job "pipeline-a-feedback-digest" "agent-a" "$SCAN_A_FEEDBACK" "$MODEL_FLASH"
add_job "pipeline-a-verify-notify" "agent-a" "$SCAN_A_VERIFY" "$MODEL_FLASH"

dedupe_cron_by_name "pipeline-a-feedback-digest"

echo ""
log "Cron 定义（均为 disabled，由 dispatch 触发）:"
jq -r '.jobs[] | "\(.id)\t\(.enabled)\t\(.name)\t\(.agentId)"' "$CRON_JSON" 2>/dev/null || openclaw cron list || true

echo ""
log "下一步:"
echo "  1. 安装 dispatch timer:  ./scripts/setup-cron.sh --install-timer"
echo "  2. 试跑（只看条件）:     VERBOSE=1 DRY_RUN=1 ./scripts/cron-dispatch.sh"
echo "  3. Gateway 在线:         openclaw gateway status"

if [[ "$INSTALL_TIMER" -eq 1 ]]; then
  install_dispatch_timer
fi

log "完成。"
