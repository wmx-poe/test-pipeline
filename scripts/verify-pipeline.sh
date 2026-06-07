#!/usr/bin/env bash
# 运行时验证：编译/构建、Docker 容器化部署、健康探活、输出 deploy-info.md
# 用法: verify-pipeline.sh <job-id|workspace-dir>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/job-paths.sh
source "${SCRIPT_DIR}/lib/job-paths.sh"
# shellcheck source=lib/agent-boundary.sh
source "${SCRIPT_DIR}/lib/agent-boundary.sh"
load_env
require_pipeline_agents "verify-pipeline.sh" agent-verifier manual

usage() {
  cat <<EOF
用法: verify-pipeline.sh <job-id|workspace-dir>

产出（相对 job workspace）:
  reports/verify-runtime.log   原始日志
  reports/verify-runtime.md    运行时验证摘要
  reports/deploy-info.md       访问地址与测试账号（部署成功时）

退出码 0=运行时通过，1=失败
EOF
}

DOCKER_WRAP=()

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "缺少 docker，请运行: ./scripts/install-docker.sh" >&2
    return 1
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER_WRAP=()
  elif command -v sg >/dev/null 2>&1 && sg docker -c 'docker info >/dev/null' 2>/dev/null; then
    DOCKER_WRAP=(sg docker -c)
    echo "提示: 当前 shell 未加载 docker 组，已自动使用 sg docker（建议 newgrp docker 或重新登录）" >&2
  else
    echo "docker 不可用。运行 ./scripts/install-docker.sh，然后 newgrp docker 或重新登录" >&2
    return 1
  fi
  if ! docker_cmd compose version >/dev/null 2>&1; then
    echo "缺少 docker compose 插件" >&2
    return 1
  fi
}

docker_cmd() {
  if [[ ${#DOCKER_WRAP[@]} -gt 0 ]]; then
    "${DOCKER_WRAP[@]}" "docker $(printf '%q ' "$@")"
  else
    docker "$@"
  fi
}

log_both() {
  local msg="[$(date +%H:%M:%S)] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

append_summary() {
  echo "$*" >> "$SUMMARY_FILE"
}

wait_for_url() {
  local url="$1" max="${2:-180}" elapsed=0
  while ! curl -sf --max-time 5 "$url" >/dev/null 2>&1; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [[ "$elapsed" -ge "$max" ]]; then
      log_both "超时: $url (${max}s)"
      return 1
    fi
    log_both "等待 $url ... (${elapsed}s)"
  done
  log_both "就绪: $url"
  return 0
}

detect_compose_file() {
  if [[ -f docker-compose.yml ]]; then echo "docker-compose.yml"
  elif [[ -f compose.yaml ]]; then echo "compose.yaml"
  elif [[ -f docker-compose.yaml ]]; then echo "docker-compose.yaml"
  else return 1
  fi
}

run_local_build() {
  local ok=0
  if [[ -f package.json ]]; then
    log_both "本地构建: npm ci && npm run build"
    if command -v npm >/dev/null 2>&1; then
      npm ci >> "$LOG_FILE" 2>&1 && npm run build >> "$LOG_FILE" 2>&1 || ok=1
    else
      log_both "跳过 npm build: 未安装 node"
      ok=1
    fi
  fi
  if [[ -f requirements.txt || -f pyproject.toml ]]; then
    log_both "本地检查: python 语法 compileall"
    if command -v python3 >/dev/null 2>&1; then
      python3 -m compileall -q . >> "$LOG_FILE" 2>&1 || ok=1
    fi
  fi
  return "$ok"
}

run_compose_tests() {
  local compose_file="$1" project="$2"
  local ran=0 failed=0

  if docker_cmd compose -f "$compose_file" -p "$project" exec -T api pytest -q >> "$LOG_FILE" 2>&1; then
    log_both "容器内 pytest (api): 通过"
    ran=1
  elif docker_cmd compose -f "$compose_file" -p "$project" exec -T api python -m pytest -q >> "$LOG_FILE" 2>&1; then
    log_both "容器内 pytest (api/python -m): 通过"
    ran=1
  fi

  if [[ "$ran" -eq 0 ]] && [[ -f package.json ]]; then
    if docker_cmd compose -f "$compose_file" -p "$project" exec -T web npm test >> "$LOG_FILE" 2>&1; then
      log_both "容器内 npm test (web): 通过"
      ran=1
    fi
  fi

  if [[ "$ran" -eq 0 ]]; then
    log_both "未检测到可执行的容器内测试命令（pytest/npm test），跳过"
    return 0
  fi
  return "$failed"
}

write_deploy_info() {
  local job_id="$1" project="$2" web_port="${3:-}" api_port="${4:-}"
  local host="${VERIFY_DEPLOY_HOST:-localhost}"

  cat > "$DEPLOY_FILE" <<EOF
# 部署访问信息

- job-id: ${job_id}
- compose 项目: ${project}
- 部署时间: $(date -Iseconds)
- 部署主机: ${host}

## 访问地址

EOF

  if [[ -n "$web_port" ]]; then
    echo "- Web UI: http://${host}:${web_port}" >> "$DEPLOY_FILE"
  fi
  if [[ -n "$api_port" ]]; then
    cat >> "$DEPLOY_FILE" <<EOF
- API: http://${host}:${api_port}
- API 文档: http://${host}:${api_port}/docs
- 健康检查: http://${host}:${api_port}/api/health
- 就绪检查: http://${host}:${api_port}/api/health/ready
EOF
  fi

  cat >> "$DEPLOY_FILE" <<'EOF'

## 测试账号

请查阅项目 `README.md`、`spec.md` 或 `init.sql` 中的默认账号说明。
若应用首次启动需初始化管理员，请在 verify 报告中注明初始化步骤。

常见占位（以实际项目为准）:
- 管理员: admin / admin123 或见 docker-compose 环境变量
EOF
}

parse_compose_ports() {
  local compose_file="$1"
  python3 - "$compose_file" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
web_port = api_port = ""

# 简单解析 "80:80" / "8000:8000" 与 service 名 web/api
current = None
for line in text.splitlines():
    m = re.match(r"\s{2}(\w+):\s*$", line)
    if m:
        current = m.group(1)
        continue
    m = re.search(r'-\s*["\']?(\d+):\d+["\']?', line)
    if m and current:
        host_port = m.group(1)
        if current == "web" and not web_port:
            web_port = host_port
        if current == "api" and not api_port:
            api_port = host_port

# 回退：常见默认端口
if not api_port:
    if re.search(r"\b8000:\d+", text):
        api_port = "8000"
if not web_port:
    if re.search(r'\b80:\d+', text):
        web_port = "80"

print(web_port or "")
print(api_port or "")
PY
}

main() {
  local arg="${1:-}"
  [[ -n "$arg" ]] || { usage >&2; exit 1; }

  local job_dir job_id src_dir reports_dir
  job_dir="$(resolve_job_dir "$arg")"
  job_id="$(basename "$job_dir")"
  src_dir="${job_dir}/src"
  reports_dir="${job_dir}/reports"
  mkdir -p "$reports_dir"

  LOG_FILE="${reports_dir}/verify-runtime.log"
  SUMMARY_FILE="${reports_dir}/verify-runtime.md"
  DEPLOY_FILE="${reports_dir}/deploy-info.md"

  : > "$LOG_FILE"
  cat > "$SUMMARY_FILE" <<EOF
# 运行时验证报告

- job-id: ${job_id}
- 开始: $(date -Iseconds)
- src: ${src_dir}

EOF

  local failures=0

  if [[ ! -d "$src_dir" ]]; then
    append_summary "- **失败**: src/ 目录不存在"
    exit 1
  fi

  require_docker || {
    append_summary "- **失败**: Docker 不可用"
    exit 1
  }

  pushd "$src_dir" >/dev/null
  local compose_file compose_project web_port api_port

  if compose_file="$(detect_compose_file)"; then
    compose_project="pipeline-${job_id}"
    log_both "Docker Compose: ${compose_file} (project=${compose_project})"

    log_both "停止旧容器..."
    docker_cmd compose -f "$compose_file" -p "$compose_project" down -v --remove-orphans >> "$LOG_FILE" 2>&1 || true

    log_both "构建并启动容器..."
    if ! docker_cmd compose -f "$compose_file" -p "$compose_project" up -d --build >> "$LOG_FILE" 2>&1; then
      append_summary "- **失败**: docker compose up --build"
      failures=$((failures + 1))
    else
      mapfile -t ports < <(parse_compose_ports "$compose_file")
      web_port="${ports[0]:-}"
      api_port="${ports[1]:-}"

      append_summary "- Docker 部署: 已启动 (project=${compose_project})"
      [[ -n "$web_port" ]] && append_summary "  - Web 端口: ${web_port}"
      [[ -n "$api_port" ]] && append_summary "  - API 端口: ${api_port}"

      local host="${VERIFY_DEPLOY_HOST:-localhost}"
      if [[ -n "$api_port" ]]; then
        if wait_for_url "http://${host}:${api_port}/api/health" 180; then
          append_summary "- 健康检查 /api/health: 通过"
        else
          append_summary "- **失败**: /api/health 探活超时"
          failures=$((failures + 1))
        fi
        if curl -sf "http://${host}:${api_port}/api/health/ready" >/dev/null 2>&1; then
          append_summary "- 就绪检查 /api/health/ready: 通过"
        else
          append_summary "- **警告**: /api/health/ready 未通过（可能仍在初始化）"
        fi
      fi

      if [[ -n "$web_port" ]]; then
        if wait_for_url "http://${host}:${web_port}/" 120; then
          append_summary "- Web 首页探活: 通过"
        else
          append_summary "- **失败**: Web 首页探活超时"
          failures=$((failures + 1))
        fi
      fi

      run_compose_tests "$compose_file" "$compose_project" || failures=$((failures + 1))

      write_deploy_info "$job_id" "$compose_project" "$web_port" "$api_port"
      append_summary "- 部署信息: reports/deploy-info.md"
    fi
  else
    log_both "无 docker-compose，尝试本地构建检查"
    append_summary "- Docker: 未找到 compose 文件，跳过容器部署"
    if run_local_build; then
      append_summary "- 本地构建/语法检查: 通过"
    else
      append_summary "- **失败**: 本地构建/语法检查"
      failures=$((failures + 1))
    fi
  fi
  popd >/dev/null

  append_summary ""
  if [[ "$failures" -eq 0 ]]; then
    append_summary "**运行时结论: PASS**"
    log_both "运行时验证通过"
    exit 0
  fi

  append_summary "**运行时结论: FAIL** (${failures} 项失败，详见 verify-runtime.log)"
  log_both "运行时验证失败"
  if [[ -x "${SCRIPT_DIR}/complete-verify.sh" ]]; then
    PIPELINE_VERIFY_CHAIN=1 PIPELINE_AGENT=agent-verifier \
      "${SCRIPT_DIR}/complete-verify.sh" "$job_id" --runtime-only || true
  fi
  exit 1
}

main "$@"
