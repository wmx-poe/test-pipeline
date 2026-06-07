#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/om-tasks.sh
source "${SCRIPT_DIR}/lib/om-tasks.sh"
load_env

PROJECT="${1:-}"
[[ -n "$PROJECT" ]] || { echo "用法: om-task-list.sh <project>" >&2; exit 1; }

dir="$(om_tasks_dir "$PROJECT")"
[[ -d "$dir" ]] || { echo "无任务"; exit 0; }

for f in "$dir"/om-*.md; do
  [[ -f "$f" ]] || continue
  id="$(basename "$f" .md)"
  st="$(grep '^status:' "$f" | head -1 | awk '{print $2}')"
  title="$(grep '^title:' "$f" | head -1 | sed 's/^title: //')"
  echo "${id}  [${st}]  ${title}"
done
