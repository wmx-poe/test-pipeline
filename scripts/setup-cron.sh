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

SCAN_DESIGN="【铁律】非用户指令禁止越界；禁止手改 status.json。入口 pending→designing 已由 cron-dispatch/job-transition 完成。扫描 status=designing：validate-spec 已通过则用 Stitch MCP（仅本 Agent 可用）产出 design/；designing 无 DESIGN.md 为卡死续跑。完成后 PIPELINE_AGENT=agent-design job-transition.sh --to design_done。无任务 NO_REPLY。"
SCAN_CODER="【铁律】非用户指令禁止越界；禁止 Stitch；禁止手改 status。入口 implementing 已由 dispatch 推进。扫描 status=implementing：用 claude-pipeline.sh implement/resume；fix_needed 须读 bugs.md+verify-feedback.md。完成后 job-transition.sh --to impl_done。无任务 NO_REPLY。"
SCAN_VERIFY="【铁律】非用户指令禁止越界；禁止 Stitch；禁止手改 status。入口 verifying 已由 dispatch 推进。扫描 status=verifying：verify-pipeline + claude-pipeline verify；complete-verify 自动设 verified/fix_needed。verified 未 delivered 则补交付。无任务 NO_REPLY。"
SCAN_FEEDBACK="【铁律】非用户指令禁止越界；禁止 Stitch；禁止改 status/spec/src。只写 feedback/inbox/*.md。扫描 delivered/raw，无新内容 NO_REPLY。"
SCAN_A_FEEDBACK="【铁律】非用户指令禁止越界；禁止 Stitch；禁止手改 status。只处理 feedback/inbox digest（不含 processed/）。verify_paused 由 feishu-notify-scan 推送。无新反馈 NO_REPLY。"
SCAN_OM="【铁律】非用户指令禁止越界；禁止 Stitch/claude-pipeline；禁止改 src/、手推 job 入口 status。只 exec om-task-* 与 report-bug.sh。ops/inbox pending→claim→complete；代码缺陷 report-bug 交 coder。无任务 NO_REPLY。"

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
add_job "pipeline-feedback-scan" "agent-feedback" "$SCAN_FEEDBACK" "$MODEL_FLASH"
add_job "pipeline-a-feedback-digest" "agent-a" "$SCAN_A_FEEDBACK" "$MODEL_FLASH"
add_job "pipeline-om-scan" "agent-om" "$SCAN_OM" "$MODEL_FLASH"

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
