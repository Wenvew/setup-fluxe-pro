#!/usr/bin/env bash
# modules/06-portainer.sh — Portainer via template (envsubst)

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia — Portainer no Swarm (via Traefik)
Pré: Docker [3], Swarm+Rede [4]. Com Traefik [5], terá TLS automático com DNS-01.
GUIDE
echo

docker info >/dev/null || die "Docker não está rodando."
[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ] || die "Swarm não está ativo ([4])."

# Coleta + revisão
while true; do
  prompt_var NETWORK_NAME   "Rede overlay (já existente)" "${NETWORK_NAME:-network_public}"
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || die "Rede '$NETWORK_NAME' não existe."
  prompt_var PORTAINER_HOST "Host do Portainer (FQDN)" "${PORTAINER_HOST:-portainer.${DOMAIN:-fluxe.one}}"

  echo
  echo "Resumo:"
  echo "  NETWORK_NAME   : $NETWORK_NAME"
  echo "  PORTAINER_HOST : $PORTAINER_HOST"
  read -r -p "Confirmar e continuar? [S/n]: " OK; OK="${OK:-S}"
  [[ "$OK" =~ ^[sS]$ ]] && break
done

command -v envsubst >/dev/null || (apt update && apt install -y gettext-base)
export NETWORK_NAME PORTAINER_HOST

install -d -m 0750 /srv/infra/portainer || true
STACK_OUT="/srv/infra/portainer/portainer-stack.yml"
log "Renderizando template templates/portainer-stack.yml.tpl -> ${STACK_OUT}"
envsubst < templates/portainer-stack.yml.tpl > "${STACK_OUT}"

log "Deploy stack 'portainer'"
docker stack deploy -c "${STACK_OUT}" portainer

sleep 5
log "Status:"
docker service ps portainer_portainer || true

echo
log "Checklist:"
echo "  1) A-record na Cloudflare: ${PORTAINER_HOST} -> IP da VPS (DNS only recomendado no primeiro teste)"
echo "  2) Acesse: https://${PORTAINER_HOST}/  (primeiro acesso define senha do admin)"
echo
log "Teste rápido:"
curl -I "https://${PORTAINER_HOST}/" || true

log "OK: Portainer publicado em https://${PORTAINER_HOST} ✅"
