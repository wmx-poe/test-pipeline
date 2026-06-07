#!/usr/bin/env bash
# 列出可部署服务器（agent-a 让用户选择）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/deploy-servers.sh
source "${SCRIPT_DIR}/lib/deploy-servers.sh"
load_env

local_ip="$("${SCRIPT_DIR}/detect-pipeline-host-ip.sh")"

echo "可部署服务器（用户必须指定 --server <id>）："
echo ""
echo "  [local]  流水线本机验证服务器"
echo "           IP: ${local_ip}（VERIFY_DEPLOY_HOST / 本地 docker 验证）"
echo "           用途: 验证阶段 runtime 探活"
echo ""

if [[ -n "${DEPLOY_SERVER_PROD_HOST:-}" ]]; then
  echo "  [prod]   生产 VPS"
  echo "           Host: ${DEPLOY_SERVER_PROD_HOST}"
  echo "           User: ${DEPLOY_SERVER_PROD_USER:-root}"
  echo "           Port: ${DEPLOY_SERVER_PROD_PORT:-22}"
  echo "           Root: ${DEPLOY_SERVER_PROD_DEPLOY_ROOT:-/opt/pipeline-deploy}"
  echo ""
else
  echo "  [prod]   （未配置 — 请在 config/.env 设置 DEPLOY_SERVER_PROD_HOST）"
  echo ""
fi

json="$(deploy_servers_json)"
if [[ -f "$json" ]]; then
  jq -r '.servers[] | select(.id != "local") | "  [\(.id)]  \(.name // .id)\n           Host: \(.host)\n"' "$json" 2>/dev/null || true
fi

echo "部署前请让用户选择 server id，再 om-task-create.sh --type deploy --server <id>"
