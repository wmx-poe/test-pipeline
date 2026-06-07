#!/usr/bin/env bash
# Agent 职责边界：限制各 pipeline 脚本只能由指定 OpenClaw Agent 调用。
# 见 docs/AGENT-BOUNDARIES.md

pipeline_boundary_strict() {
  [[ "${PIPELINE_BOUNDARY_STRICT:-1}" != "0" ]]
}

# 解析当前调用方 Agent（优先级：PIPELINE_AGENT > OPENCLAW_AGENT_ID > 父进程推断）
pipeline_resolve_agent() {
  if [[ -n "${PIPELINE_AGENT:-}" ]]; then
    printf '%s\n' "$PIPELINE_AGENT"
    return 0
  fi
  if [[ -n "${OPENCLAW_AGENT_ID:-}" ]]; then
    printf '%s\n' "$OPENCLAW_AGENT_ID"
    return 0
  fi

  local pid args agent
  pid="${PPID:-0}"
  while [[ "$pid" -gt 1 ]]; do
    args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
    if [[ "$args" =~ agent:([a-z0-9-]+):cron ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    if [[ "$args" =~ --agent[[:space:]]+([a-z0-9-]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)"
  done

  printf '%s\n' "unknown"
}

# require_pipeline_agents <script-name> <allowed-agent>...
# 特殊允许：manual；verify-chain（PIPELINE_VERIFY_CHAIN=1 时）
require_pipeline_agents() {
  local script="$1"
  shift
  local allowed=("$@")

  pipeline_boundary_strict || return 0

  if [[ -n "${PIPELINE_VERIFY_CHAIN:-}" ]]; then
    local a
    for a in "${allowed[@]}"; do
      [[ "$a" == "verify-chain" ]] && return 0
    done
  fi

  local agent
  agent="$(pipeline_resolve_agent)"

  if [[ "$agent" == "manual" ]]; then
    return 0
  fi

  local a
  for a in "${allowed[@]}"; do
    [[ "$agent" == "$a" ]] && return 0
  done

  {
    echo "边界拒绝: ${script} 仅允许由 ${allowed[*]} 调用" >&2
    echo "  当前: PIPELINE_AGENT=${PIPELINE_AGENT:-（未设置）} OPENCLAW_AGENT_ID=${OPENCLAW_AGENT_ID:-（未设置）} 推断=${agent}" >&2
    echo "  人工运维: PIPELINE_AGENT=manual ${script} ..." >&2
    echo "  临时关闭: PIPELINE_BOUNDARY_STRICT=0 ${script} ..." >&2
    echo "  详见: docs/AGENT-BOUNDARIES.md" >&2
  }
  exit 3
}
