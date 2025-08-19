#!/usr/bin/env bash
# modules/03-docker.sh — Instala Docker (repo oficial) e ajusta daemon.json

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

log "Instalando Docker (repositório oficial)"
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

log "Escrevendo /etc/docker/daemon.json (DNS + rotação de logs + buildkit)"
cat >/etc/docker/daemon.json <<'JSON'
{
  "dns": ["1.1.1.1", "1.0.0.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "features": { "buildkit": true }
}
JSON

systemctl restart docker
docker --version && docker info --format 'Swarm: {{.Swarm.LocalNodeState}}' || true
log "Docker instalado e ativo ✅"
