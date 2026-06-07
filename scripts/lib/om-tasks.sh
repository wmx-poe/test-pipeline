#!/usr/bin/env bash
# 运维任务（ops/）路径与 status.json 读写

project_ops_dir() {
  local project="$1"
  echo "$(project_root "$project")/ops"
}

ensure_ops_layout() {
  local project="$1"
  local ops
  ops="$(project_ops_dir "$project")"
  mkdir -p \
    "${ops}/inbox" \
    "${ops}/running" \
    "${ops}/reports" \
    "${ops}/done"
  if [[ ! -f "${ops}/status.json" ]]; then
    cat > "${ops}/status.json" <<EOF
{
  "updatedAt": "$(date -Iseconds)",
  "tasks": {}
}
EOF
  fi
}

ops_status_file() {
  local project="$1"
  echo "$(project_ops_dir "$project")/status.json"
}

new_om_task_id() {
  echo "om-$(date +%Y%m%d-%H%M%S)"
}
