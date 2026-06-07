#!/usr/bin/env bash
# agent-om 认领 pending 运维任务
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
load_env

PROJECT="${1:-}"
[[ -n "$PROJECT" ]] || { echo "用法: om-task-claim.sh <project>" >&2; exit 1; }

dir="$(om_tasks_dir "$PROJECT")"
[[ -d "$dir" ]] || { echo "无运维任务目录"; exit 1; }

for f in "$dir"/om-*.md; do
  [[ -f "$f" ]] || continue
  grep -q '^status: pending' "$f" 2>/dev/null || continue
  sed -i 's/^status: pending/status: in_progress/' "$f"
  echo "claimed: $(basename "$f")"
  echo "$f"
  exit 0
done
echo "无 pending 任务"
exit 1
