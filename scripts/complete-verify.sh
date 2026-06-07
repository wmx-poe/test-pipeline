#!/usr/bin/env bash
# 根据 verify-runtime.md / verify.md 自动更新 status.json（fix_needed | verified | verify_paused）
# 用法: complete-verify.sh <job-id|workspace-dir> [--runtime-only|--full]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "complete-verify.sh" agent-verifier verify-chain manual

usage() {
  cat <<EOF
用法: complete-verify.sh <job-id|workspace-dir> [--runtime-only|--full]

  --runtime-only  仅读 verify-runtime.md；FAIL → fix_needed（触发 coder）
  --full          读 verify-runtime.md + verify.md；PASS → verified，FAIL → fix_needed 或 verify_paused

退出码: 0=PASS/已处理, 1=FAIL（fix_needed）, 2=参数或文件错误

默认 maxVerifyRounds=10：同一 job 内自动修复最多 10 轮；超限 → verify_paused + verify-user-report.md，由用户决定是否 continue-verify.sh。
EOF
}

write_verify_user_report() {
  local job_dir="$1" round="$2" max_r="$3" runtime_v="$4" verify_v="$5"
  local report="${job_dir}/reports/verify-user-report.md"
  local log_file="${job_dir}/reports/verify-runtime.log"
  local runtime_md="${job_dir}/reports/verify-runtime.md"
  local verify_md="${job_dir}/reports/verify.md"
  local job_id
  job_id="$(basename "$job_dir")"
  local now
  now="$(date -Iseconds)"

  cat > "$report" <<EOF
# 验证暂停 — 待用户决定（${job_id}）

> 生成于 ${now}，已连续 **${round}** 轮未通过（上限 ${max_r} 轮）

## 摘要

- **任务**: ${job_id}
- **运行时结论**: ${runtime_v}
- **综合审查结论**: ${verify_v}
- **当前状态**: \`verify_paused\`（流水线已停止自动修复）

## 关键报错（运行时）

EOF

  if [[ -f "$runtime_md" ]]; then
    grep -iE '失败|FAIL|error|Error|异常' "$runtime_md" 2>/dev/null | head -15 >> "$report" || true
  fi
  if [[ -f "$log_file" ]]; then
    echo "" >> "$report"
    echo '```' >> "$report"
    tail -40 "$log_file" >> "$report" 2>/dev/null || true
    echo '```' >> "$report"
  fi

  cat >> "$report" <<EOF

## 关键报错（综合审查）

EOF

  if [[ -f "$verify_md" ]]; then
    grep -iE 'FAIL|失败|阻塞|严重|Bug|error' "$verify_md" 2>/dev/null | head -20 >> "$report" || true
  fi

  cat >> "$report" <<EOF

## 请您决定

1. **继续修复** — 回复「继续」或「继续验证」；Agent A 将执行：
   \`${PIPELINE_ROOT}/scripts/continue-verify.sh ${job_id} --rounds 10 --by feishu-user\`
   （再自动跑最多 10 轮）
2. **暂停 / 改需求** — 说明原因；可在飞书补充需求或 Bug 描述（仍用原 job，不开新 job）
3. **放弃本任务** — 回复「放弃」；可人工将 status 设为 \`verify_failed\`

详细阻塞项见 \`reports/verify-feedback.md\`。
EOF

  rm -f "${job_dir}/reports/.verify-paused-notified"
  log "已写入用户报告: ${report}"
}

read_runtime_verdict() {
  local f="$1"
  [[ -f "$f" ]] || { echo "missing"; return; }
  if grep -qE '\*\*运行时结论: PASS\*\*|运行时结论: PASS' "$f" 2>/dev/null; then
    echo "pass"
  elif grep -qE '\*\*运行时结论: FAIL\*\*|运行时结论: FAIL' "$f" 2>/dev/null; then
    echo "fail"
  else
    echo "unknown"
  fi
}

read_verify_verdict() {
  local f="$1"
  [[ -f "$f" ]] || { echo "missing"; return; }
  local last
  last="$(grep -E '结论[：:]\s*(PASS|FAIL)|verdict:\s*(PASS|FAIL)' "$f" 2>/dev/null | tail -1 || true)"
  if [[ "$last" =~ PASS ]]; then
    echo "pass"
  elif [[ "$last" =~ FAIL ]]; then
    echo "fail"
  else
    echo "unknown"
  fi
}

write_verify_feedback() {
  local job_dir="$1" round="$2" runtime_v="$3" verify_v="$4"
  local feedback="${job_dir}/reports/verify-feedback.md"
  local runtime_md="${job_dir}/reports/verify-runtime.md"
  local verify_md="${job_dir}/reports/verify.md"

  cat > "$feedback" <<EOF
# 验证修复清单 (round ${round})

> 由 \`complete-verify.sh\` 自动生成于 $(date -Iseconds)

## 判定

- 运行时: ${runtime_v}
- 综合审查: ${verify_v}

## 阻塞项（摘自报告）

EOF

  if [[ -f "$runtime_md" ]] && [[ "$runtime_v" == "fail" ]]; then
    echo "### verify-runtime.md" >> "$feedback"
    grep -E '^\*\*失败|失败\*\*|FAIL' "$runtime_md" 2>/dev/null | head -20 >> "$feedback" || true
    echo "" >> "$feedback"
  fi
  if [[ -f "$verify_md" ]] && [[ "$verify_v" == "fail" ]]; then
    echo "### verify.md" >> "$feedback"
    grep -iE '严重|Bug|FAIL|阻塞|失败' "$verify_md" 2>/dev/null | head -30 >> "$feedback" || true
    echo "" >> "$feedback"
  fi

  cat >> "$feedback" <<EOF
## 下一步（agent-coder）

1. 读本文件与 \`verify-runtime.md\`、\`verify.md\`
2. \`status\` → \`implementing\`，修复后 → \`impl_done\`
3. 重跑 \`${PIPELINE_ROOT}/scripts/verify-pipeline.sh\` 验证
EOF
}

apply_status() {
  local job_dir="$1" phase="$2" overall="$3" runtime_v="$4" verify_v="$5"
  local status_file="${job_dir}/status.json"
  local job_id
  job_id="$(basename "$job_dir")"
  local now
  now="$(date -Iseconds)"

  python3 - <<PY
import json
from pathlib import Path

job_dir = Path("${job_dir}")
status_path = job_dir / "status.json"
data = json.loads(status_path.read_text(encoding="utf-8"))
now = "${now}"
phase = "${phase}"
overall = "${overall}"
runtime_v = "${runtime_v}"
verify_v = "${verify_v}"
job_id = "${job_id}"

data.setdefault("verifyRound", 0)
max_default = int(data.get("maxVerifyRounds", 10) or 10)
if max_default <= 0:
    max_default = 10
data.setdefault("maxVerifyRounds", max_default)
current = data.get("status", "")
history = data.setdefault("history", [])

def append_history(frm, to, by, note=""):
    entry = {"at": now, "from": frm, "to": to, "by": "complete-verify.sh"}
    if note:
        entry["note"] = note
    history.append(entry)

if overall == "pass":
    if current != "verified":
        append_history(current, "verified", "complete-verify.sh",
                       f"runtime={runtime_v} verify={verify_v}")
    data["status"] = "verified"
    data["updatedAt"] = now
    status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK: {job_id} -> verified")
    print("RESULT:pass")
    raise SystemExit(0)

round_next = int(data["verifyRound"]) + 1
data["verifyRound"] = round_next
max_r = int(data.get("maxVerifyRounds", 10) or 10)
if max_r <= 0:
    max_r = 10
    data["maxVerifyRounds"] = max_r

target = "fix_needed"
note = f"phase={phase} runtime={runtime_v} verify={verify_v} round={round_next}/{max_r}"
if round_next > max_r:
    target = "verify_paused"
    note = f"已达 maxVerifyRounds={max_r}，等待用户决定是否继续"

append_history(current, target, "complete-verify.sh", note)
data["status"] = target
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if target == "fix_needed":
    print(f"OK: {job_id} -> fix_needed (round {round_next}/{max_r})")
    print("RESULT:fix_needed")
    raise SystemExit(1)
print(f"OK: {job_id} -> verify_paused (round {round_next}>{max_r})", file=__import__("sys").stderr)
print("RESULT:verify_paused")
raise SystemExit(1)
PY
}

main() {
  local phase="full"
  local job_arg=""

  for arg in "$@"; do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
      --runtime-only) phase="runtime" ;;
      --full) phase="full" ;;
      *) job_arg="$arg" ;;
    esac
  done

  [[ -n "$job_arg" ]] || { usage >&2; exit 2; }

  local job_dir runtime_md verify_md runtime_v verify_v overall
  job_dir="$(resolve_job_dir "$job_arg")"
  runtime_md="${job_dir}/reports/verify-runtime.md"
  verify_md="${job_dir}/reports/verify.md"

  runtime_v="$(read_runtime_verdict "$runtime_md")"
  verify_v="$(read_verify_verdict "$verify_md")"

  if [[ "$phase" == "runtime" ]]; then
    if [[ "$runtime_v" == "missing" ]]; then
      echo "complete-verify: 缺少 verify-runtime.md" >&2
      exit 2
    fi
    if [[ "$runtime_v" == "pass" ]]; then
      echo "complete-verify: 运行时 PASS，等待综合审查"
      exit 0
    fi
    overall="fail"
  else
    if [[ "$runtime_v" == "fail" || "$verify_v" == "fail" ]]; then
      overall="fail"
    elif [[ "$runtime_v" == "pass" && "$verify_v" == "pass" ]]; then
      overall="pass"
    else
      echo "complete-verify: 无法判定（runtime=${runtime_v} verify=${verify_v}）" >&2
      exit 2
    fi
  fi

  if [[ "$overall" == "fail" ]]; then
    local round=1
    if [[ -f "${job_dir}/status.json" ]]; then
      round="$(python3 -c "import json;print(json.load(open('${job_dir}/status.json')).get('verifyRound',0)+1)")"
    fi
    write_verify_feedback "$job_dir" "$round" "$runtime_v" "$verify_v"
  fi

  apply_status "$job_dir" "$phase" "$overall" "$runtime_v" "$verify_v" || true

  if [[ -f "${job_dir}/status.json" ]] \
    && [[ "$(jq -r '.status' "${job_dir}/status.json")" == "verify_paused" ]]; then
    local max_r paused_round
    paused_round="$(jq -r '.verifyRound' "${job_dir}/status.json")"
    max_r="$(jq -r '.maxVerifyRounds' "${job_dir}/status.json")"
    write_verify_user_report "$job_dir" "$paused_round" "$max_r" "$runtime_v" "$verify_v"
  fi
}

main "$@"
