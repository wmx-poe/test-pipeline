#!/usr/bin/env bash
# status.json 完整性校验：防止手改 status 欺骗 cron-dispatch timer。
# 规则：① history 末条 to 须与当前 status 一致；② 各 status 须有对应产物/来源脚本。

# 校验单个 job 工作区是否可信地处于 $want 状态（供 cron-dispatch 使用）
# 返回 0=可信，1=不可信（手改或缺产物）
status_integrity_ok() {
  local job_dir="$1" want="$2"
  [[ -d "$job_dir" ]] || return 1
  local status_file="${job_dir}/status.json"
  [[ -f "$status_file" ]] || return 1

  python3 - "$job_dir" "$want" <<'PY'
import json
import sys
from pathlib import Path

job_dir = Path(sys.argv[1])
want = sys.argv[2]
status_path = job_dir / "status.json"

try:
    data = json.loads(status_path.read_text(encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    sys.exit(1)

current = data.get("status", "")
if current != want:
    sys.exit(1)

history = data.get("history") or []
strict = bool(history)
if strict:
    last = history[-1]
    if last.get("to") != current:
        sys.exit(1)

def has_file(rel: str) -> bool:
    return (job_dir / rel).is_file()

def last_by() -> str:
    if not history:
        return ""
    return str(history[-1].get("by", ""))

# 各状态：产物门禁 + history.by 白名单（防仅改 status 字段）
def by_ok(*names: str) -> bool:
    if not strict:
        return True
    return last_by() in names

checks = {
    "draft": lambda: True,
    "pending": lambda: has_file("spec.md") and by_ok(
        "promote-job.sh", "new-job.sh", "job-transition.sh"
    ),
    "designing": lambda: by_ok("job-transition.sh", "cron-dispatch.sh"),
    "design_done": lambda: has_file("design/DESIGN.md") and by_ok("job-transition.sh"),
    "design_failed": lambda: by_ok("job-transition.sh"),
    "implementing": lambda: by_ok("job-transition.sh", "cron-dispatch.sh"),
    "impl_done": lambda: (
        has_file("reports/implement-summary.md") and by_ok("job-transition.sh")
    ),
    "verifying": lambda: by_ok("job-transition.sh", "cron-dispatch.sh"),
    "verified": lambda: (
        has_file("reports/verify.md")
        and by_ok("complete-verify.sh", "job-transition.sh")
    ),
    "fix_needed": lambda: (
        (has_file("reports/verify-feedback.md") or has_file("reports/bugs.md"))
        and by_ok(
            "complete-verify.sh", "report-bug.sh", "continue-verify.sh", "reopen-job.sh"
        )
    ),
    "verify_paused": lambda: by_ok("complete-verify.sh"),
    "verify_failed": lambda: by_ok(
        "complete-verify.sh", "job-transition.sh", "continue-verify.sh"
    ),
    "delivered": lambda: True,
}

checker = checks.get(want)
if checker is None:
    sys.exit(1)
if not checker():
    sys.exit(1)
sys.exit(0)
PY
}

# 遍历可信的 job 目录（status 字段匹配且通过完整性校验）
each_job_status_trusted() {
  local want="$1" jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    status_integrity_ok "$jobdir" "$want" || continue
    printf '%s\n' "$jobdir"
  done < <(each_job_status "$want")
}

has_job_status_trusted() {
  local want="$1" jobdir
  while IFS= read -r jobdir; do
    [[ -n "$jobdir" ]] || continue
    status_integrity_ok "$jobdir" "$want" && return 0
  done < <(each_job_status "$want")
  return 1
}
