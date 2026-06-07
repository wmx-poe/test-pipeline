#!/usr/bin/env bash
# agent-a 下发运维任务 → ops/inbox/<id>.md + status.json pending
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
# shellcheck source=lib/deploy-servers.sh
source "${SCRIPT_DIR}/lib/deploy-servers.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "om-task-create.sh" agent-a manual

usage() {
  cat <<EOF
用法: om-task-create.sh <project> --type deploy|logs|diagnose|custom --title "标题" \\
  [--job-id <job-id>] [--server <server-id>] [--priority P0|P1|P2|P3] [--body "正文或步骤"] [--by agent-a]

--type deploy 时 **必须** 指定 --server（见 deploy-servers-list.sh）。

示例:
  om-task-create.sh proj-xxx --type deploy --server prod --title "部署到生产" \\
    --job-id job-xxx --body "rsync src 后 docker compose up -d 并探活"
  om-task-create.sh proj-xxx --type logs --title "收集 API 日志" \\
    --job-id job-xxx --body "docker logs api 最近 200 行"
EOF
}

main() {
  local project="" type="" title="" job_id="" server_id="" priority="P2" body="" by="agent-a"
  [[ $# -ge 1 ]] || { usage >&2; exit 1; }
  project="$1"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --type) type="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --job-id) job_id="${2:-}"; shift 2 ;;
      --server) server_id="${2:-}"; shift 2 ;;
      --priority) priority="${2:-P2}"; shift 2 ;;
      --body) body="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  [[ -n "$project" && -n "$type" && -n "$title" ]] || { usage >&2; exit 1; }
  [[ -d "$(project_root "$project")" ]] || { echo "项目不存在: $project" >&2; exit 1; }

  if [[ "$type" == "deploy" ]]; then
    if [[ -z "$server_id" ]]; then
      echo "deploy 任务必须指定 --server；可选服务器：" >&2
      deploy_servers_list_ids >&2 || true
      exit 1
    fi
    deploy_server_resolve "$server_id" >/dev/null || exit 1
  elif [[ -n "$server_id" ]]; then
    deploy_server_resolve "$server_id" >/dev/null || exit 1
  fi

  local server_json="" server_host="" server_name="" ssh_target="" deploy_root=""
  if [[ -n "$server_id" ]]; then
    server_json="$(deploy_server_resolve "$server_id")"
    server_host="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("host",""))' "$server_json")"
    server_name="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("name",""))' "$server_json")"
    ssh_target="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("sshTarget") or "")' "$server_json")"
    deploy_root="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("deployRoot") or "")' "$server_json")"
  fi

  ensure_ops_layout "$project"
  local task_id now inbox_file
  task_id="$(new_om_task_id)"
  now="$(date -Iseconds)"
  inbox_file="$(project_ops_dir "$project")/inbox/${task_id}.md"

  local job_yaml="null"
  [[ -n "$job_id" ]] && job_yaml="\"${job_id}\""

  local server_block=""
  if [[ -n "$server_id" ]]; then
    server_block="serverId: ${server_id}
serverHost: ${server_host}
serverName: \"${server_name//\"/\\\"}\"
sshTarget: ${ssh_target:-null}
deployRoot: ${deploy_root:-null}
"
  fi

  cat > "$inbox_file" <<EOF
---
id: ${task_id}
project: ${project}
type: ${type}
status: pending
jobId: ${job_id:-null}
${server_block}priority: ${priority}
createdAt: ${now}
createdBy: ${by}
title: "${title//\"/\\\"}"
---

# ${title}

## 背景

${body:-（见下方步骤）}

$( [[ -n "$server_id" ]] && cat <<SERV

## 目标服务器

| 项 | 值 |
|----|-----|
| serverId | \`${server_id}\` |
| 名称 | ${server_name} |
| 地址 | ${server_host} |
| SSH | ${ssh_target:-本机执行} |
| 部署根目录 | ${deploy_root:-（见 job src）} |

SERV
)

## 步骤

${body:+1. ${body}}
$( [[ "$type" == "deploy" && -n "$ssh_target" ]] && echo "2. 通过 SSH \`${ssh_target}\` 在 \`${deploy_root}\` 下部署（rsync/scp job src 后 docker compose up -d）并探活" )
$( [[ "$type" == "deploy" && -z "$ssh_target" ]] && echo "2. 在本机 \`jobs/<job-id>/src\` 下 docker compose up -d 并探活" )

## 验收

- 在 \`ops/reports/${task_id}.md\` 写入执行摘要与关键输出

EOF

  local ops_dir
  ops_dir="$(project_ops_dir "$project")"

  python3 - <<PY
import json
from pathlib import Path

project = "${project}"
task_id = "${task_id}"
status_path = Path("${ops_dir}") / "status.json"
now = "${now}"
by = "${by}"
type_ = "${type}"
title = """${title}"""
job_id = """${job_id}"""
priority = "${priority}"

data = json.loads(status_path.read_text(encoding="utf-8"))
tasks = data.setdefault("tasks", {})
entry = {
    "status": "pending",
    "type": type_,
    "title": title,
    "jobId": job_id or None,
    "priority": priority,
    "createdAt": now,
    "createdBy": by,
    "claimedAt": None,
    "completedAt": None,
    "report": None,
}
server_id = """${server_id}"""
if server_id:
    entry["serverId"] = server_id
    entry["serverHost"] = """${server_host}"""
tasks[task_id] = entry
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {task_id} -> pending")
print(f"inbox: {status_path.parent / 'inbox' / (task_id + '.md')}")
PY
}

main "$@"
