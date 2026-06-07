#!/usr/bin/env bash
# 检测 test-pipeline 部署机 IP，供本地验证（VERIFY_DEPLOY_HOST）使用
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env

detect_ip() {
  local ip=""
  # 优先 env 显式配置
  if [[ -n "${PIPELINE_HOST_IP:-}" ]]; then
    echo "$PIPELINE_HOST_IP"
    return 0
  fi
  # 默认路由出口 IP
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
  fi
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [[ -z "$ip" ]]; then
    ip="127.0.0.1"
  fi
  echo "$ip"
}

main() {
  local ip
  ip="$(detect_ip)"
  if [[ "${1:-}" == "--export" ]]; then
    echo "export VERIFY_DEPLOY_HOST=${ip}"
  else
    echo "$ip"
  fi
}

main "$@"
