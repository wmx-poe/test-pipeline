#!/usr/bin/env bash
# Job pointer ↔ pipeline-workspace 路径解析
# 依赖 load_env() 已设置 PIPELINE_ROOT、WORKSPACE_ROOT

jobs_index_dir() {
  echo "${PIPELINE_ROOT}/pipeline/jobs"
}

slugify_project() {
  local title="$1" job_id="$2"
  python3 - "$title" "$job_id" <<'PY'
import re
import sys

title = sys.argv[1]
job_id = sys.argv[2]

slug = title.lower()
slug = re.sub(r"[^a-z0-9]+", "-", slug)
slug = re.sub(r"-+", "-", slug).strip("-")
slug = slug[:40].strip("-")
if not slug:
    suffix = job_id[4:] if job_id.startswith("job-") else job_id
    slug = f"proj-{suffix}"
print(slug)
PY
}

unique_project_slug() {
  local base="$1"
  local slug="$base" n=2
  while [[ -d "${WORKSPACE_ROOT}/${slug}" ]]; do
    slug="${base}-${n}"
    n=$((n + 1))
  done
  echo "$slug"
}

job_pointer() {
  local job_id="$1"
  echo "$(jobs_index_dir)/${job_id}/job.md"
}

job_index_dir() {
  local job_id="$1"
  echo "$(jobs_index_dir)/${job_id}"
}

project_root() {
  local project="$1"
  echo "${WORKSPACE_ROOT}/${project}"
}

project_feedback_dir() {
  local project="$1"
  echo "${WORKSPACE_ROOT}/${project}/feedback"
}

project_delivered_dir() {
  local project="$1"
  echo "${WORKSPACE_ROOT}/${project}/delivered"
}

# 从 job.md frontmatter 读取字段（id/project/title/workspace）
pointer_field() {
  local pointer="$1" field="$2"
  [[ -f "$pointer" ]] || return 1
  awk -v f="$field" '
    BEGIN { in_fm=0 }
    /^---$/ { if (++n == 1) { in_fm=1; next } else if (n == 2) { exit } }
    in_fm && $0 ~ "^" f ": " {
      sub("^" f ": ", "")
      print
      exit
    }
  ' "$pointer"
}

read_job_workspace() {
  local job_id="$1"
  local pointer ws
  pointer="$(job_pointer "$job_id")"
  if [[ ! -f "$pointer" ]]; then
    echo "找不到 job 指针: $pointer" >&2
    return 1
  fi
  ws="$(pointer_field "$pointer" workspace)"
  [[ -n "$ws" && -d "$ws" ]] || {
    echo "job 工作区无效: ${ws:-<empty>} (pointer: $pointer)" >&2
    return 1
  }
  echo "$ws"
}

read_job_project() {
  local job_id="$1"
  local pointer project
  pointer="$(job_pointer "$job_id")"
  [[ -f "$pointer" ]] || return 1
  project="$(pointer_field "$pointer" project)"
  [[ -n "$project" ]] || return 1
  echo "$project"
}

delivered_dir_for_job() {
  local job_id="$1"
  local project
  project="$(read_job_project "$job_id")" || return 1
  echo "$(project_delivered_dir "$project")/${job_id}"
}

resolve_job_dir() {
  local arg="$1"
  local job_id ws pointer

  if [[ -d "$arg" && -f "$arg/spec.md" ]]; then
    echo "$arg"
    return 0
  fi

  if [[ -f "$arg" && "$(basename "$arg")" == "job.md" ]]; then
    ws="$(pointer_field "$arg" workspace)"
    [[ -n "$ws" && -d "$ws" && -f "$ws/spec.md" ]] || {
      echo "指针未指向有效工作区: $arg" >&2
      return 1
    }
    echo "$ws"
    return 0
  fi

  job_id="$(basename "$arg")"
  if [[ "$job_id" == job-* ]]; then
    ws="$(read_job_workspace "$job_id")" && echo "$ws" && return 0
  fi

  pointer="${jobs_index_dir}/${arg}/job.md"
  if [[ -f "$pointer" ]]; then
    ws="$(pointer_field "$pointer" workspace)"
    [[ -n "$ws" && -d "$ws" && -f "$ws/spec.md" ]] || {
      echo "指针未指向有效工作区: $pointer" >&2
      return 1
    }
    echo "$ws"
    return 0
  fi

  echo "找不到任务目录或 spec.md: $arg" >&2
  return 1
}

each_job_pointer() {
  local d pointer index
  index="$(jobs_index_dir)"
  [[ -d "$index" ]] || return 0
  for d in "$index"/job-*; do
    [[ -d "$d" ]] || continue
    pointer="${d}/job.md"
    [[ -f "$pointer" ]] || continue
    printf '%s\n' "$pointer"
  done
}

each_job_workspace() {
  local pointer ws
  while IFS= read -r pointer; do
    [[ -n "$pointer" ]] || continue
    ws="$(pointer_field "$pointer" workspace)"
    [[ -n "$ws" && -d "$ws" ]] || continue
    printf '%s\n' "$ws"
  done < <(each_job_pointer)
}

each_status_json() {
  local ws
  while IFS= read -r ws; do
    [[ -f "${ws}/status.json" ]] || continue
    printf '%s\n' "${ws}/status.json"
  done < <(each_job_workspace)
}

each_job_status() {
  local want="$1" f jobdir
  while IFS= read -r f; do
    jq -e --arg s "$want" '.status == $s' "$f" >/dev/null 2>&1 || continue
    jobdir="$(dirname "$f")"
    printf '%s\n' "$jobdir"
  done < <(each_status_json)
}

has_job_status() {
  local want="$1" f
  while IFS= read -r f; do
    jq -e --arg s "$want" '.status == $s' "$f" >/dev/null 2>&1 && return 0
  done < <(each_status_json)
  return 1
}

ensure_project_layout() {
  local project="$1"
  mkdir -p \
    "$(project_root "$project")/jobs" \
    "$(project_delivered_dir "$project")" \
    "$(project_feedback_dir "$project")/raw" \
    "$(project_feedback_dir "$project")/inbox/processed"
}

write_job_pointer() {
  local job_id="$1" project="$2" title="$3" workspace="$4" created_at="$5"
  local index_dir pointer
  index_dir="$(job_index_dir "$job_id")"
  pointer="$(job_pointer "$job_id")"
  mkdir -p "$index_dir"
  cat > "$pointer" <<EOF
---
id: ${job_id}
project: ${project}
title: "${title}"
workspace: ${workspace}
createdAt: "${created_at}"
---
# Job: ${title}

> 工作区：\`${workspace}\`
EOF
}
