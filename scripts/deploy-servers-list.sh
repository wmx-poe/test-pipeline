#!/usr/bin/env bash
# 列出可部署目标服务器（agent-a 飞书展示 / om-task-create 校验）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/deploy-servers.sh
source "${SCRIPT_DIR}/lib/deploy-servers.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "deploy-servers-list.sh" agent-a agent-om manual

usage() {
  cat <<EOF
用法: deploy-servers-list.sh [--json] [--default]

列出部署目标：静态项见 config/deploy-servers.json；生产 VPS IP 见 config/.env（DEPLOY_SERVER_PROD_*）。
agent-a 在用户请求部署时 **必须先展示列表** 并请用户选择 server id。

示例:
  deploy-servers-list.sh
  deploy-servers-list.sh --json
EOF
}

main() {
  local format="table" show_default=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --json) format="json"; shift ;;
      --default) show_default=1; shift ;;
      *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  _deploy_servers_load

  if [[ "$show_default" -eq 1 ]]; then
    python3 - <<'PY'
import json, os
data = json.loads(os.environ["DEPLOY_SERVERS_JSON"])
print(data.get("defaultServer", ""))
PY
    exit 0
  fi

  if [[ "$format" == "json" ]]; then
    echo "$DEPLOY_SERVERS_JSON"
    exit 0
  fi

  python3 - <<'PY'
import json, os
data = json.loads(os.environ["DEPLOY_SERVERS_JSON"])
default = data.get("defaultServer", "")
print("部署目标服务器（请选择 id）：")
print()
for i, s in enumerate(data.get("servers", []), 1):
    mark = " [默认]" if s["id"] == default else ""
    ssh = s.get("sshTarget") or "(本机，无 SSH)"
    root = s.get("deployRoot") or "-"
    notes = s.get("notes") or ""
    print(f"{i}. {s['id']}{mark}")
    print(f"   名称: {s.get('name', s['id'])}")
    print(f"   地址: {s.get('host', '-')}")
    print(f"   SSH:  {ssh}")
    print(f"   部署根目录: {root}")
    if notes:
        print(f"   备注: {notes}")
    print()
print("下发 deploy 任务时使用: om-task-create.sh ... --type deploy --server <id>")
ids = {s["id"] for s in data.get("servers", [])}
if "prod" not in ids and not os.environ.get("DEPLOY_SERVER_PROD_HOST", "").strip():
    print("提示: 生产机未配置。请在 config/.env 设置 DEPLOY_SERVER_PROD_HOST 等后重新 deploy。")
PY
}

main "$@"
