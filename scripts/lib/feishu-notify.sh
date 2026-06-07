#!/usr/bin/env bash
# 飞书主动推送（openclaw message send，无 LLM）
set -euo pipefail

_feishu_notify_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

feishu_notify_enabled() {
  [[ "${FEISHU_NOTIFY_ENABLED:-1}" != "0" ]] \
    && [[ -n "${FEISHU_NOTIFY_TARGET:-}" ]]
}

feishu_notify_openclaw() {
  export PATH="${HOME}/.local/node/bin:${HOME}/.local/npm-global/bin:${PATH}"
  command -v openclaw >/dev/null 2>&1
}

feishu_job_title() {
  local status_file="$1"
  jq -r '.title // .id // "未知任务"' "$status_file" 2>/dev/null || echo "未知任务"
}

feishu_job_id_from_dir() {
  basename "$1"
}

feishu_notify_marker() {
  local job_dir="$1" milestone="$2"
  echo "${job_dir}/reports/.feishu-notified-${milestone}"
}

feishu_already_notified() {
  local job_dir="$1" milestone="$2"
  [[ -f "$(feishu_notify_marker "$job_dir" "$milestone")" ]]
}

feishu_mark_notified() {
  local job_dir="$1" milestone="$2"
  mkdir -p "${job_dir}/reports"
  date -Iseconds > "$(feishu_notify_marker "$job_dir" "$milestone")"
}

feishu_send_message() {
  local text="$1"
  if ! feishu_notify_enabled; then
    return 0
  fi
  if ! feishu_notify_openclaw; then
    echo "[feishu-notify] 跳过：未找到 openclaw" >&2
    return 0
  fi
  if openclaw message send \
    --channel feishu \
    --target "${FEISHU_NOTIFY_TARGET}" \
    -m "$text" 2>&1; then
    return 0
  fi
  echo "[feishu-notify] 发送失败（见 openclaw logs）" >&2
  return 1
}

feishu_verify_paused_excerpt() {
  local job_dir="$1"
  local report="${job_dir}/reports/verify-user-report.md"
  local runtime_md="${job_dir}/reports/verify-runtime.md"
  local lines=""

  if [[ -f "$report" ]]; then
    lines="$(sed -n '/## 关键报错/,/^## /p' "$report" 2>/dev/null \
      | grep -v '^##' | grep -v '^$' | head -8 || true)"
  fi
  if [[ -z "$lines" && -f "$runtime_md" ]]; then
    lines="$(grep -iE 'FAIL|失败|error|Error|异常' "$runtime_md" 2>/dev/null | head -6 || true)"
  fi
  if [[ -z "$lines" ]]; then
    lines="（详见 reports/verify-user-report.md）"
  fi
  printf '%s' "$lines"
}

feishu_build_job_message() {
  local milestone="$1" job_dir="$2"
  local status_file="${job_dir}/status.json"
  local job_id title round max_r excerpt deploy_hint

  job_id="$(feishu_job_id_from_dir "$job_dir")"
  title="$(feishu_job_title "$status_file")"

  case "$milestone" in
    pending)
      cat <<EOF
📋 【Pipeline】任务已入队

任务: ${job_id}
标题: ${title}
状态: pending → 即将开始设计
EOF
      ;;
    design_done)
      cat <<EOF
🎨 【Pipeline】设计完成

任务: ${job_id}
标题: ${title}
状态: design_done → 开始开发实现
EOF
      ;;
    impl_done)
      cat <<EOF
💻 【Pipeline】开发完成

任务: ${job_id}
标题: ${title}
状态: impl_done → 开始自动验证
EOF
      ;;
    verified)
      deploy_hint=""
      if [[ -f "${job_dir}/reports/deploy-info.md" ]]; then
        deploy_hint=$'\n部署: reports/deploy-info.md'
      fi
      cat <<EOF
✅ 【Pipeline】验证通过

任务: ${job_id}
标题: ${title}
状态: verified → 准备交付${deploy_hint}
EOF
      ;;
    verify_paused)
      round="$(jq -r '.verifyRound // 0' "$status_file" 2>/dev/null || echo 0)"
      max_r="$(jq -r '.maxVerifyRounds // 10' "$status_file" 2>/dev/null || echo 10)"
      excerpt="$(feishu_verify_paused_excerpt "$job_dir")"
      cat <<EOF
⏸ 【Pipeline】验证暂停 — 需您决定

任务: ${job_id}
标题: ${title}
轮次: 第 ${round}/${max_r} 轮未通过，已停止自动修复

关键问题:
${excerpt}

继续: 飞书回复「继续修复」，或执行
  ${PIPELINE_ROOT}/scripts/continue-verify.sh ${job_id} --rounds 10 --by feishu-user
放弃: 回复「放弃」或不再操作
EOF
      ;;
    delivered)
      cat <<EOF
📦 【Pipeline】已交付

任务: ${job_id}
标题: ${title}
产物已复制到项目 delivered/ 目录
EOF
      ;;
    *)
      echo "未知 milestone: $milestone" >&2
      return 1
      ;;
  esac
}

feishu_build_om_message() {
  local project="$1" task_id="$2" status="$3" summary="$4"
  local icon="🔧"
  [[ "$status" == "failed" ]] && icon="❌"
  cat <<EOF
${icon} 【Pipeline】运维任务${status}

项目: ${project}
任务: ${task_id}
摘要: ${summary:-（见 ops/reports/${task_id}.md）}
EOF
}

# 发送 job 里程碑；成功发送后写 marker。已通知则跳过。
feishu_notify_job_milestone() {
  local job_dir="$1" milestone="$2"
  local msg

  if ! feishu_notify_enabled; then
    return 0
  fi
  if feishu_already_notified "$job_dir" "$milestone"; then
    return 0
  fi

  msg="$(feishu_build_job_message "$milestone" "$job_dir")"
  if feishu_send_message "$msg"; then
    feishu_mark_notified "$job_dir" "$milestone"
    echo "[feishu-notify] ${milestone} -> $(feishu_job_id_from_dir "$job_dir")"
  fi
}

feishu_notify_om_task() {
  local project="$1" task_id="$2" status="$3" summary="${4:-}"
  local ops marker msg
  ops="${WORKSPACE_ROOT}/${project}/ops"
  marker="${ops}/.feishu-notified-${task_id}-${status}"

  if ! feishu_notify_enabled; then
    return 0
  fi
  [[ -f "$marker" ]] && return 0

  msg="$(feishu_build_om_message "$project" "$task_id" "$status" "$summary")"
  if feishu_send_message "$msg"; then
    date -Iseconds > "$marker"
    echo "[feishu-notify] om ${task_id} -> ${status}"
  fi
}
