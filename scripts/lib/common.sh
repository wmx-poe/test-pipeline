#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

load_env() {
  if [[ -f "${REPO_ROOT}/config/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "${REPO_ROOT}/config/.env"
    set +a
  fi
  export PIPELINE_ROOT="${PIPELINE_ROOT:-$REPO_ROOT}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "缺少命令: $cmd" >&2
    exit 1
  fi
}

substitute_workspace_files() {
  local dir="$1"
  find "$dir" -type f \( -name '*.md' -o -name '*.toml' \) -print0 | while IFS= read -r -d '' f; do
    if grep -q '{{PIPELINE_ROOT}}' "$f" 2>/dev/null; then
      sed -i "s|{{PIPELINE_ROOT}}|${PIPELINE_ROOT}|g" "$f"
    fi
  done
}

log() { echo "[$(date +%H:%M:%S)] $*"; }
