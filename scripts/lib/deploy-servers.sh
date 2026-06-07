#!/usr/bin/env bash
# 部署目标服务器：config/deploy-servers.json + .env 注入（生产 IP 不写死在 JSON）

deploy_servers_config() {
  echo "${PIPELINE_ROOT}/config/deploy-servers.json"
}

_deploy_servers_resolved_json() {
  local cfg
  cfg="$(deploy_servers_config)"
  [[ -f "$cfg" ]] || { echo "缺少服务器配置: $cfg" >&2; return 1; }
  python3 - <<'PY'
import json, os
from pathlib import Path

cfg = Path(os.environ["DEPLOY_SERVERS_CFG"])
raw = json.loads(cfg.read_text(encoding="utf-8"))
out_servers = []
for s in raw.get("servers", []):
    entry = dict(s)
    if s.get("source") == "env":
        host = os.environ.get(s.get("envHost", ""), "").strip()
        if not host:
            continue
        user = os.environ.get(s.get("envUser", ""), "root").strip() or "root"
        root = os.environ.get(s.get("envDeployRoot", ""), "/opt/pipeline-apps").strip()
        name = os.environ.get(s.get("envName", ""), "").strip() or s.get("name", s["id"])
        entry["host"] = host
        entry["user"] = user
        entry["sshTarget"] = f"{user}@{host}" if user else host
        entry["deployRoot"] = root
        entry["name"] = name
        entry["notes"] = s.get("notes", "")
    else:
        user = s.get("user")
        host = s.get("host", "")
        if user:
            entry["sshTarget"] = f"{user}@{host}"
        else:
            entry["sshTarget"] = None
    for k in ("source", "envHost", "envUser", "envDeployRoot", "envName"):
        entry.pop(k, None)
    out_servers.append(entry)

default = raw.get("defaultServer", "local")
ids = {s["id"] for s in out_servers}
if default not in ids and out_servers:
    default = out_servers[0]["id"]

print(json.dumps({"defaultServer": default, "servers": out_servers}, ensure_ascii=False))
PY
}

_deploy_servers_load() {
  export DEPLOY_SERVERS_CFG="$(deploy_servers_config)"
  DEPLOY_SERVERS_JSON="$(_deploy_servers_resolved_json)" || return 1
  export DEPLOY_SERVERS_JSON
}

deploy_server_resolve() {
  local server_id="${1:-}"
  _deploy_servers_load || return 1
  python3 - <<'PY' "$server_id"
import json, os, sys
server_id = sys.argv[1] if len(sys.argv) > 1 else ""
data = json.loads(os.environ["DEPLOY_SERVERS_JSON"])
servers = {s["id"]: s for s in data.get("servers", [])}
if not server_id:
    server_id = data.get("defaultServer", "")
if server_id not in servers:
    known = ", ".join(sorted(servers)) or "(无，请检查 config/.env 中 DEPLOY_SERVER_PROD_HOST)"
    print(f"未知服务器 id: {server_id!r}，可选: {known}", file=sys.stderr)
    sys.exit(1)
print(json.dumps(servers[server_id], ensure_ascii=False))
PY
}

deploy_servers_list_ids() {
  _deploy_servers_load || return 1
  python3 - <<'PY'
import json, os
data = json.loads(os.environ["DEPLOY_SERVERS_JSON"])
for s in data.get("servers", []):
    print(s["id"])
PY
}

deploy_server_ssh_target() {
  local server_id="$1"
  local info
  info="$(deploy_server_resolve "$server_id")" || return 1
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); print(s.get("sshTarget") or "")' "$info"
}

deploy_server_is_remote() {
  local server_id="$1"
  local target
  target="$(deploy_server_ssh_target "$server_id")"
  [[ -n "$target" ]]
}
