#!/usr/bin/env bash
# modules/02-install-traefik.sh — Instala Traefik v3 no Swarm com Cloudflare DNS-01

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

# 1) Coleta de variáveis (persistidas em .env)
prompt_var DOMAIN        "Informe o seu domínio raiz (gerenciado pela Cloudflare)" "${DOMAIN:-fluxe.one}"
prompt_var TRAEFIK_HOST  "Informe o host do dashboard do Traefik" "${TRAEFIK_HOST:-teste-traefik.${DOMAIN}}"
prompt_var ACME_EMAIL    "E-mail para o Let's Encrypt (ACME)" "${ACME_EMAIL:-infra@${DOMAIN}}"
prompt_var DASH_USER     "Usuário para o dashboard" "${DASH_USER:-superadmin}"
prompt_secret DASH_PWD   "Senha do dashboard (BasicAuth)"
prompt_secret CF_API_TOKEN "Cloudflare API Token (Zone:Read + DNS:Edit)"

# 2) Docker (repositório oficial) + daemon.json
log "Instalando Docker e habilitando serviços"
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

log "Configurando /etc/docker/daemon.json (DNS + logs)"
cat >/etc/docker/daemon.json <<'JSON'
{
  "dns": ["1.1.1.1", "1.0.0.1", "8.8.8.8"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "features": { "buildkit": true }
}
JSON
systemctl restart docker

# 3) Kernel/network ajustes
log "Ajustando rede (br_netfilter, ip_forward)"
modprobe br_netfilter || true
cat >/etc/sysctl.d/99-swarm-overlays.conf <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
sysctl -w net.ipv4.ip_forward=1
sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf && echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl --system >/dev/null

# 4) Swarm + overlay
PUBIP="$(detect_pubip)"; log "PUBIP=$PUBIP"
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
  docker swarm init --advertise-addr "$PUBIP"
fi
docker network inspect network_public >/dev/null 2>&1 || \
docker network create --driver overlay --attachable network_public

# 5) Estrutura Traefik
log "Criando estrutura /srv/infra/traefik"
install -d -m 0750 /srv/infra/traefik/{acme,logs}
install -d -m 0700 /srv/infra/traefik/.secrets

# 6) Secret Cloudflare
printf "%s" "$CF_API_TOKEN" | tr -d '\r\n' > /srv/infra/traefik/.secrets/cf_token.txt
chmod 0400 /srv/infra/traefik/.secrets/cf_token.txt
docker secret rm cf_token_v2 2>/dev/null || true
docker secret create cf_token_v2 /srv/infra/traefik/.secrets/cf_token.txt

# 7) BasicAuth usersfile
log "Gerando usersfile (BasicAuth)"
docker run --rm httpd:2.4-alpine htpasswd -nbB "$DASH_USER" "$DASH_PWD" > /srv/infra/traefik/usersfile
grep -v '^[[:space:]]*$' /srv/infra/traefik/usersfile | head -n1 > /srv/infra/traefik/usersfile.clean && mv /srv/infra/traefik/usersfile.clean /srv/infra/traefik/usersfile
chmod 0400 /srv/infra/traefik/usersfile

# 8) Template do stack
log "Escrevendo traefik-stack.yml a partir do template"
TEMPLATE="templates/traefik-stack.yml.tpl"
OUT="/srv/infra/traefik/traefik-stack.yml"
# Substituição simples (cuidado com / em valores)
sed -e "s|\${ACME_EMAIL}|${ACME_EMAIL}|g" \
    -e "s|\${TRAEFIK_HOST}|${TRAEFIK_HOST}|g" \
    "$TEMPLATE" > "$OUT"

export ACME_EMAIL TRAEFIK_HOST

# 9) Deploy
log "Validando YAML"
docker compose -f "$OUT" config >/dev/null && log "YAML OK"
log "Fazendo deploy do Traefik"
docker stack deploy -c "$OUT" traefik

# 10) Acompanhamento
log "Acompanhando logs por 30s (ACME/Let’s Encrypt)"
timeout 30s bash -c 'docker service logs -f --since 2m traefik_traefik | egrep -Ei "acme|letsencrypt|dns|challenge|certificate|error|warn" || true'

# 11) Testes básicos
log "Testando HTTPS + dashboard"
curl -I "https://${TRAEFIK_HOST}/dashboard/" || warn "Falhou o HEAD; tente GET autenticado"
curl -s -u "${DASH_USER}:${DASH_PWD}" "https://${TRAEFIK_HOST}/dashboard/" | head -n 3 || true

log "Traefik pronto em: https://${TRAEFIK_HOST}/dashboard/"
