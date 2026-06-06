#!/usr/bin/env bash
# 根据 verify-runtime.md / verify.md 自动更新 status.json（fix_needed | verified | verify_failed）
# 用法: complete-verify.sh <job-id|workspace-dir> [--runtime-only|--full]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
load_env

usage() {
  cat <<EOF
用法: complete-verify.sh <job-id|workspace-dir> [--runtime-only|--full]

  --runtime-only  仅读 verify-runtime.md；FAIL → fix_needed（触发 coder）
  --full          读 verify-runtime.md + verify.md；PASS → verified，FAIL → fix_needed

退出码: 0=PASS/已处理, 1=FAIL/verify_failed, 2=参数或文件错误
EOF
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
data.setdefault("maxVerifyRounds", 3)
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
    raise SystemExit(0)

# fail
round_next = int(data["verifyRound"]) + 1
data["verifyRound"] = round_next
max_r = int(data["maxVerifyRounds"])

if round_next <= max_r:
    target = "fix_needed"
    append_history(current, target, "complete-verify.sh",
                   f"phase={phase} runtime={runtime_v} verify={verify_v} round={round_next}")
    data["status"] = target
    data["updatedAt"] = now
    status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK: {job_id} -> fix_needed (round {round_next}/{max_r})")
    raise SystemExit(1)

target = "verify_failed"
append_history(current, target, "complete-verify.sh",
               f"超过 maxVerifyRounds={max_r}")
data["status"] = target
data["updatedAt"] = now
status_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {job_id} -> verify_failed (round {round_next}>{max_r})", file=__import__("sys").stderr)
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

  apply_status "$job_dir" "$phase" "$overall" "$runtime_v" "$verify_v"
}

main "$@"
