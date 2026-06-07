#!/usr/bin/env bash
# 部署服务器配置（local=流水线本机；生产从 .env 读取）
set -euo pipefail

deploy_servers_json() {
  echo "${PIPELINE_ROOT}/config/deploy-servers.json"
}

deploy_server_field() {
  local id="$1" field="$2"
  local json
  json="$(deploy_servers_json)"
  [[ -f "$json" ]] || return 1
  jq -r --arg id "$id" --arg f "$field" '
    .servers[] | select(.id==$id) | .[$f] // empty
  ' "$json" 2>/dev/null
}

resolve_deploy_host() {
  local id="$1"
  local host user port deploy_root
  case "$id" in
    local|pipeline)
      "${PIPELINE_ROOT}/scripts/detect-pipeline-host-ip.sh"
      return 0
      ;;
    prod|production)
      host="${DEPLOY_SERVER_PROD_HOST:-}"
      [[ -n "$host" ]] || { echo "未配置 DEPLOY_SERVER_PROD_HOST（见 config/.env）" >&2; return 1; }
      echo "$host"
      return 0
      ;;
  esac
  host="$(deploy_server_field "$id" host)"
  [[ -n "$host" && "$host" != "null" ]] || return 1
  echo "$host"
}

resolve_deploy_ssh() {
  local id="$1"
  local host user port
  host="$(resolve_deploy_host "$id")" || return 1
  case "$id" in
    prod|production)
      user="${DEPLOY_SERVER_PROD_USER:-root}"
      port="${DEPLOY_SERVER_PROD_PORT:-22}"
      ;;
    local|pipeline)
      user="${USER:-root}"
      port="22"
      ;;
    *)
      user="$(deploy_server_field "$id" user)"
      port="$(deploy_server_field "$id" port)"
      user="${user:-root}"
      port="${port:-22}"
      ;;
  esac
  echo "${user}@${host}:${port}"
}
