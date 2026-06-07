#!/usr/bin/env bash
# Ubuntu 22.04+ 从零安装 Docker（验证阶段 verify-pipeline.sh 必需）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export DEBIAN_FRONTEND=noninteractive

log() { echo "[install-docker] $*"; }
die() { echo "[install-docker] 错误: $*" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then
  ELEVATE=""
  TARGET_USER="${SUDO_USER:-${INSTALL_DOCKER_USER:-$(logname 2>/dev/null || echo wmx)}}"
else
  TARGET_USER="$(whoami)"
  if sudo -n true 2>/dev/null; then
    ELEVATE="sudo"
  elif command -v pkexec >/dev/null 2>&1; then
    ELEVATE="pkexec"
    log "sudo 需密码，改用 pkexec（桌面会弹出授权框）"
  else
    die "需要 root：配置 sudo 免密或安装 polkit (pkexec)"
  fi
fi

run_root() {
  if [[ -z "$ELEVATE" ]]; then
    "$@"
  elif [[ "$ELEVATE" == "sudo" ]]; then
    sudo "$@"
  else
    pkexec "$@"
  fi
}

# ── 1. 系统包 ────────────────────────────────────────────────
log "更新 apt 索引..."
run_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
log "安装 docker.io、docker-compose-v2、uidmap..."
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io docker-compose-v2 uidmap curl ca-certificates

# ── 2. 镜像加速（国内网络拉镜像）────────────────────────────
if [[ ! -f /etc/docker/daemon.json ]] || ! grep -q registry-mirrors /etc/docker/daemon.json 2>/dev/null; then
  log "配置 Docker 镜像加速..."
  run_root bash -c 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io"
  ]
}
EOF'
fi

# ── 3. 服务 ──────────────────────────────────────────────────
log "启用并启动 docker 服务..."
run_root systemctl enable docker
run_root systemctl restart docker
run_root systemctl is-active docker >/dev/null || die "docker 服务未运行"

# ── 4. 用户权限 ──────────────────────────────────────────────
if id "$TARGET_USER" >/dev/null 2>&1; then
  if groups "$TARGET_USER" | grep -q '\bdocker\b'; then
    log "用户 ${TARGET_USER} 已在 docker 组"
  else
    log "将 ${TARGET_USER} 加入 docker 组..."
    run_root usermod -aG docker "$TARGET_USER"
    log "已加入 docker 组。请 newgrp docker 或重新登录"
  fi
fi

# ── 5. 验证 ──────────────────────────────────────────────────
verify_docker() {
  docker --version
  docker compose version
  docker info >/dev/null 2>&1
}

if verify_docker 2>/dev/null; then
  log "Docker 验证通过（当前用户可直接使用）"
elif command -v sg >/dev/null 2>&1 && sg docker -c 'docker info >/dev/null' 2>/dev/null; then
  log "Docker 验证通过（使用 sg docker；请 newgrp docker 或重新登录以永久生效）"
else
  log "当前 shell 尚无 docker 组，用 root 做冒烟测试..."
  run_root docker run --rm hello-world >/dev/null || die "hello-world 失败，检查网络与镜像加速"
  log "Docker 引擎正常（请 newgrp docker 后无需 root）"
fi

log "安装完成。"
cat <<EOF

后续:
  newgrp docker          # 或重新登录，使 docker 组生效
  docker info
  docker run --rm hello-world
  ${REPO_ROOT}/scripts/verify-pipeline.sh <job-id>

规范: ${REPO_ROOT}/README.md

EOF
