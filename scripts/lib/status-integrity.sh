#!/usr/bin/env bash
# status.json 容错：修复缺失字段、非法 status、损坏 JSON，避免手工改坏导致流水线卡死
# 依赖 load_env() 已设置 PIPELINE_ROOT

VALID_STATUSES=(
  draft pending designing design_done design_failed
  implementing impl_done verifying verified
  fix_needed verify_paused verify_failed delivered
)

status_is_valid() {
  local s="$1" v
  for v in "${VALID_STATUSES[@]}"; do
    [[ "$s" == "$v" ]] && return 0
  done
  return 1
}

# 根据产物推断更合理的 status（手工改错时的自愈）
status_infer_from_artifacts() {
  local job_dir="$1"
  local cur="$2"

  [[ -f "${job_dir}/reports/verify.md" ]] && [[ "$cur" == "verifying" || "$cur" == "implementing" ]] && { echo "impl_done"; return; }
  [[ -f "${job_dir}/reports/implement-summary.md" ]] && [[ "$cur" == "implementing" ]] && { echo "impl_done"; return; }
  [[ -f "${job_dir}/design/DESIGN.md" ]] && [[ "$cur" == "designing" ]] && { echo "design_done"; return; }
  [[ -f "${job_dir}/spec.md" ]] && [[ "$cur" == "draft" ]] && grep -q '{{TITLE}}' "${job_dir}/spec.md" 2>/dev/null && { echo "draft"; return; }

  echo "$cur"
}

repair_status_json() {
  local status_file="$1"
  local job_dir backup now job_id project title

  [[ -f "$status_file" ]] || return 1
  job_dir="$(dirname "$status_file")"
  now="$(date -Iseconds)"
  job_id="$(basename "$job_dir")"

  if ! python3 - "$status_file" "$job_id" "$now" <<'PY' 2>/dev/null; then
import json, sys, shutil
from pathlib import Path

path = Path(sys.argv[1])
job_id = sys.argv[2]
now = sys.argv[3]
backup = path.with_suffix(".json.bak")

try:
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
except Exception:
    if path.exists():
        shutil.copy2(path, backup)
    data = {}

if not isinstance(data, dict):
    data = {}

data.setdefault("id", job_id)
data.setdefault("project", data.get("project") or "unknown")
data.setdefault("title", data.get("title") or job_id)
data.setdefault("createdAt", data.get("createdAt") or now)
data.setdefault("updatedAt", now)
data.setdefault("createdBy", data.get("createdBy") or "unknown")
data.setdefault("assignee", data.get("assignee"))
data.setdefault("verifyRound", 0)
data.setdefault("verifyIteration", 0)
data.setdefault("maxVerifyRounds", 10)
if not isinstance(data.get("history"), list):
    data["history"] = []

valid = {
    "draft", "pending", "designing", "design_done", "design_failed",
    "implementing", "impl_done", "verifying", "verified",
    "fix_needed", "verify_paused", "verify_failed", "delivered",
}
cur = data.get("status", "draft")
if cur not in valid:
    data.setdefault("_statusRepair", {})
    data["_statusRepair"]["previous"] = cur
    data["_statusRepair"]["at"] = now
    data["status"] = "draft"

path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
    cp "$status_file" "${status_file}.corrupt.$(date +%s)" 2>/dev/null || true
    return 1
  fi

  # 产物推断（仅当 status 与产物明显矛盾时修正）
  local cur inferred
  cur="$(status_json_field "$status_file" status)"
  inferred="$(status_infer_from_artifacts "$job_dir" "$cur")"
  if [[ "$inferred" != "$cur" ]]; then
    python3 - "$status_file" "$cur" "$inferred" "$now" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
frm, to, now = sys.argv[2], sys.argv[3], sys.argv[4]
data = json.loads(path.read_text(encoding="utf-8"))
data["status"] = to
data["updatedAt"] = now
data.setdefault("history", []).append({
    "at": now, "from": frm, "to": to,
    "by": "status-integrity.sh",
    "note": "artifact-inferred repair",
})
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  fi
}

status_json_field() {
  local status_file="$1" field="$2"
  repair_status_json "$status_file" 2>/dev/null || true
  python3 - "$status_file" "$field" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
field = sys.argv[2]
try:
    data = json.loads(p.read_text(encoding="utf-8"))
    v = data.get(field)
    if v is None:
        raise SystemExit(1)
    if isinstance(v, (dict, list)):
        import json as j
        print(j.dumps(v, ensure_ascii=False))
    else:
        print(v)
except Exception:
    raise SystemExit(1)
PY
}

each_status_json_safe() {
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    repair_status_json "$f" 2>/dev/null || true
    printf '%s\n' "$f"
  done < <(each_status_json 2>/dev/null || true)
}

has_job_status_safe() {
  local want="$1" f
  while IFS= read -r f; do
    jq -e --arg s "$want" '.status == $s' "$f" >/dev/null 2>&1 && return 0
  done < <(each_status_json_safe)
  return 1
}

each_job_status_safe() {
  local want="$1" f jobdir
  while IFS= read -r f; do
    jq -e --arg s "$want" '.status == $s' "$f" >/dev/null 2>&1 || continue
    jobdir="$(dirname "$f")"
    printf '%s\n' "$jobdir"
  done < <(each_status_json_safe)
}
