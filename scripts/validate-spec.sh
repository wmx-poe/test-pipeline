#!/usr/bin/env bash
# 校验 pipeline-workspace/<project>/jobs/<job-id>/spec.md 是否已从模板变为可执行规格
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
load_env

usage() {
  cat <<EOF
用法: validate-spec.sh <job-id|job-dir|job.md> [--quiet]

校验 spec.md 是否满足入队（pending）条件。
退出码 0=通过，1=未通过。

章节标题允许编号与前缀，例如「## 1. 项目目标」「## 11. 验收标准（UAT）」。

示例:
  validate-spec.sh job-20260529-232409
  validate-spec.sh ${WORKSPACE_ROOT}/my-app/jobs/job-xxx
EOF
}

fail() {
  if [[ "${QUIET:-0}" -eq 0 ]]; then
    echo "spec 校验失败: $*" >&2
  fi
  exit 1
}

ok() {
  if [[ "${QUIET:-0}" -eq 0 ]]; then
    echo "spec 校验通过: ${JOB_DIR}"
  fi
  exit 0
}

# 匹配 ## 标题行（可含编号、括号说明），keyword 为扩展正则片段
has_heading() {
  local keyword="$1"
  grep -qE -- "^##[[:space:]]+.*(${keyword})" "$SPEC"
}

has_acceptance_criteria() {
  if grep -qE -- '^- \[[ xX]\] .+' "$SPEC"; then
    return 0
  fi
  if has_heading '验收' && grep -qE -- '^[0-9]+\.[[:space:]]+[^[:space:]].+' "$SPEC"; then
    return 0
  fi
  return 1
}

QUIET=0
JOB_ARG=""

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -q|--quiet) QUIET=1 ;;
    *) JOB_ARG="$arg" ;;
  esac
done

[[ -n "$JOB_ARG" ]] || { usage >&2; exit 1; }

JOB_DIR="$(resolve_job_dir "$JOB_ARG")"
SPEC="${JOB_DIR}/spec.md"

[[ -s "$SPEC" ]] || fail "spec.md 为空或不存在"

PLACEHOLDER_PATTERNS=(
  '{{TITLE}}'
  '{{JOB_ID}}'
  '（用户希望达成什么）'
  '（领域上下文、约束、已有系统说明）'
  '（文字摘要或录音转写）'
  '（2–3 种可行方案、权衡、推荐方案及理由；brainstorming 产出）'
  '（架构、关键组件、数据流、错误处理、测试要点；brainstorming 产出）'
  '- [ ] 标准 1'
  '- [ ] 标准 2'
)

for pat in "${PLACEHOLDER_PATTERNS[@]}"; do
  if grep -qF -- "$pat" "$SPEC"; then
    fail "仍含模板占位: ${pat}"
  fi
done

# 语义必填节（标题可编号，如「## 1. 项目目标」）
has_heading '目标' || fail "缺少目标节（例如 ## 目标 或 ## 1. 项目目标）"
has_heading '验收' || fail "缺少验收标准节（例如 ## 验收标准 或 ## 11. 验收标准（UAT））"

has_heading '背景知识|背景|约束|已确认' \
  || has_heading '架构|设计|技术方案|方案' \
  || fail "缺少背景或设计说明（例如 ## 背景知识 / ## 已确认约束 / ## 总体架构设计）"

has_heading '用户原始|原始输入|用户输入|需求来源|已确认约束' \
  || fail "缺少需求来源说明（例如 ## 用户原始输入 或 ## 已确认约束）"

has_heading '方案对比|方案选型|备选方案' \
  || has_heading '架构|总体架构|技术方案|设计摘要' \
  || fail "缺少方案或架构说明（例如 ## 方案对比 / ## 总体架构设计）"

has_heading '设计摘要|架构|总体架构|技术方案|功能需求' \
  || fail "缺少设计/实现摘要（例如 ## 设计摘要 / ## 总体架构设计 / ## 功能需求）"

has_acceptance_criteria || fail "验收标准至少需要一条可测试条目（- [ ] ... 或验收节下的编号列表 1. ...）"

if [[ "$(wc -c < "$SPEC")" -lt 400 ]]; then
  fail "spec.md 过短（<400 字节），可能未填写完整"
fi

ok
