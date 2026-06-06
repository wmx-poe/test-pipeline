#!/usr/bin/env bash
# 将旧布局 pipeline/jobs/<job-id>/* 迁移到 pipeline-workspace/<project>/jobs/<job-id>/
# 并在 pipeline/jobs/<job-id>/ 仅保留 job.md 指针
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
load_env

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<EOF
用法: migrate-job-layout.sh [--dry-run]

迁移旧版 pipeline/jobs/<job-id>/ 内联布局到 pipeline-workspace。
已存在 job.md 指针的 job 会跳过。
EOF
      exit 0
      ;;
  esac
done

migrate_job_dir() {
  local old_dir="$1"
  local job_id pointer title project base_slug workspace created_at status_file

  job_id="$(basename "$old_dir")"
  pointer="$(job_pointer "$job_id")"

  if [[ -f "$pointer" ]]; then
    log "跳过 ${job_id}：已有指针"
    return 0
  fi

  status_file="${old_dir}/status.json"
  [[ -f "$status_file" ]] || {
    log "跳过 ${job_id}：无 status.json（非旧布局）"
    return 0
  }

  title="$(jq -r '.title // empty' "$status_file")"
  [[ -n "$title" && "$title" != "null" ]] || title="$job_id"
  project="$(jq -r '.project // empty' "$status_file")"
  if [[ -z "$project" || "$project" == "null" ]]; then
    base_slug="$(slugify_project "$title" "$job_id")"
    project="$(unique_project_slug "$base_slug")"
  fi
  created_at="$(jq -r '.createdAt // empty' "$status_file")"
  [[ -n "$created_at" && "$created_at" != "null" ]] || created_at="$(date -Iseconds)"

  workspace="$(project_root "$project")/jobs/${job_id}"
  ensure_project_layout "$project"

  if [[ -d "$workspace" && "$(ls -A "$workspace" 2>/dev/null)" ]]; then
    log "错误: 目标工作区已存在且非空: $workspace" >&2
    return 1
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] ${old_dir} -> ${workspace}"
    log "[dry-run] 写指针 ${pointer}"
    return 0
  fi

  mkdir -p "$workspace"
  shopt -s dotglob nullglob
  for item in "$old_dir"/*; do
    [[ -e "$item" ]] || continue
    mv "$item" "$workspace/"
  done
  shopt -u dotglob nullglob

  jq --arg p "$project" '.project = $p' "$workspace/status.json" > "${workspace}/status.json.tmp"
  mv "${workspace}/status.json.tmp" "$workspace/status.json"

  write_job_pointer "$job_id" "$project" "$title" "$workspace" "$created_at"
  log "已迁移 ${job_id} -> ${workspace}"
}

migrate_legacy_delivered_feedback() {
  local legacy_delivered="${PIPELINE_ROOT}/pipeline/delivered"
  local legacy_raw="${PIPELINE_ROOT}/pipeline/feedback/raw"
  local legacy_inbox="${PIPELINE_ROOT}/pipeline/feedback/inbox"
  local project="default"

  ensure_project_layout "$project"

  if [[ -d "$legacy_delivered" ]] && compgen -G "${legacy_delivered}/"* >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[dry-run] 迁移 ${legacy_delivered}/* -> $(project_delivered_dir "$project")/"
    else
      mkdir -p "$(project_delivered_dir "$project")"
      shopt -s nullglob
      for d in "$legacy_delivered"/*; do
        [[ -d "$d" ]] || continue
        mv "$d" "$(project_delivered_dir "$project")/"
      done
      shopt -u nullglob
      log "已迁移 legacy delivered -> $(project_delivered_dir "$project")/"
    fi
  fi

  if [[ -d "$legacy_raw" ]] && compgen -G "${legacy_raw}/"* >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[dry-run] 迁移 ${legacy_raw}/* -> $(project_feedback_dir "$project")/raw/"
    else
      mkdir -p "$(project_feedback_dir "$project")/raw"
      shopt -s nullglob
      for f in "$legacy_raw"/*; do
        [[ -e "$f" ]] || continue
        mv "$f" "$(project_feedback_dir "$project")/raw/"
      done
      shopt -u nullglob
      log "已迁移 legacy feedback/raw"
    fi
  fi

  if [[ -d "$legacy_inbox" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[dry-run] 迁移 ${legacy_inbox}/* -> $(project_feedback_dir "$project")/inbox/"
    else
      mkdir -p "$(project_feedback_dir "$project")/inbox/processed"
      shopt -s nullglob
      for f in "$legacy_inbox"/*.md; do
        [[ -f "$f" ]] || continue
        mv "$f" "$(project_feedback_dir "$project")/inbox/"
      done
      if [[ -d "${legacy_inbox}/processed" ]]; then
        for f in "${legacy_inbox}/processed"/*; do
          [[ -e "$f" ]] || continue
          mv "$f" "$(project_feedback_dir "$project")/inbox/processed/"
        done
      fi
      shopt -u nullglob
      log "已迁移 legacy feedback/inbox"
    fi
  fi
}

log "WORKSPACE_ROOT=$WORKSPACE_ROOT"
mkdir -p "$WORKSPACE_ROOT"

shopt -s nullglob
index="$(jobs_index_dir)"
for old_dir in "$index"/job-*; do
  [[ -d "$old_dir" ]] || continue
  migrate_job_dir "$old_dir"
done
shopt -u nullglob

migrate_legacy_delivered_feedback
log "迁移完成"
