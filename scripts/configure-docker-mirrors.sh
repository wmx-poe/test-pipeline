#!/usr/bin/env bash
# 配置 Docker 拉取镜像的国内加速（daemon.json）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[configure-docker-mirrors] $*"; }

if [[ "$(id -u)" -eq 0 ]]; then
  ELEVATE=""
elif sudo -n true 2>/dev/null; then
  ELEVATE="sudo"
elif command -v pkexec >/dev/null 2>&1; then
  ELEVATE="pkexec"
else
  echo "需要 root 权限" >&2
  exit 1
fi

run_root() {
  if [[ -z "$ELEVATE" ]]; then "$@"; elif [[ "$ELEVATE" == "sudo" ]]; then sudo "$@"; else pkexec "$@"; fi
}

log "写入 /etc/docker/daemon.json（国内 registry 镜像）..."
run_root bash -c 'mkdir -p /etc/docker && cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io"
  ]
}
EOF
systemctl restart docker'

log "当前镜像源:"
sg docker -c 'docker info 2>/dev/null' | grep -A5 'Registry Mirrors' || docker info 2>/dev/null | grep -A5 'Registry Mirrors' || true
log "完成。验收: docker run --rm hello-world"
