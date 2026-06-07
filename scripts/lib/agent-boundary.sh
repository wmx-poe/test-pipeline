#!/usr/bin/env bash
# Agent 边界：脚本层校验 PIPELINE_AGENT，防止 OpenClaw 越界调用

boundary_agent() {
  echo "${PIPELINE_AGENT:-unknown}"
}

boundary_require_agent() {
  local allowed_csv="$1"
  local agent
  agent="$(boundary_agent)"
  IFS=',' read -ra allowed <<< "$allowed_csv"
  local a
  for a in "${allowed[@]}"; do
    [[ "$agent" == "$a" ]] && return 0
  done
  echo "agent-boundary: 拒绝 — 当前 PIPELINE_AGENT=${agent}，允许: ${allowed_csv}" >&2
  echo "若确需破例，请用户在飞书明确授权后再执行。" >&2
  return 1
}

boundary_require_script() {
  local script_name="$1"
  local allowed_csv="$2"
  boundary_require_agent "$allowed_csv" || return 1
  return 0
}

# 跳过流水线规则（manual / 非 timer）须用户飞书确认
boundary_require_user_override() {
  [[ "${PIPELINE_USER_OVERRIDE:-}" == "1" ]] || {
    echo "agent-boundary: 此操作跳过流水线规则，须用户在飞书明确确认后设置 PIPELINE_USER_OVERRIDE=1" >&2
    return 1
  }
}
