#!/usr/bin/env bash
# modules/06-portainer.sh — Instala Portainer CE + Agent no Swarm e publica via Traefik (TLS)

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia rápido — Portainer no Swarm (via Traefik)
1) Pré-requisitos:
   • Docker instalado (módulo [3]).
   • Swarm ativo + rede overlay (módulo [4]).
   • Traefik já instalado é opcional, mas recomendado.

2) O que vou te pedir:
   • NETWORK_NAME (ex.: network_public) — deve existir.
   • PORTAINER_HOST (ex.: portainer.seudominio.com) — precisa apontar para o IP da VPS.

3) Após publicar:
   • Acesse https://PORTAINER_HOST e crie a SENHA do admin na primeira vez.
   • Se usar Cloudflare, crie/valide o A record para o subdomínio.
GUIDE
echo

# Checagens básicas
if ! docker info >/dev/null 2>&1; then
  die "Docker não está instalado/rodando. Rode primeiro o módulo [3]."
fi
SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
[ "$SWARM_STATE" = "active" ] || die "Swarm não está ativo. Rode o módulo [4]."

# Coleta + revisão
while true; do
  prompt_var NETWORK_NAME   "Nome da rede overlay (já criada no módulo [4])" "${NETWORK_NAME:-network_public}"
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    err "Rede '$NETWORK_NAME' não existe. Rode o módulo [4] e tente novamente."
    exit 1
  fi

  DEFAULT_DOMAIN="${DOMAIN:-fluxe.one}"
  DEFAULT_PORTAINER_HOST="${PORTAINER_HOST:-portainer.${DEFAULT_DOMAIN}}"
  prompt_var PORTAINER_HOST "Host do Portainer (FQDN)" "$DEFAULT_PORTAINER_HOST"

  echo
  echo "Resumo:"
  echo "  NETWORK_NAME   : $NETWORK_NAME"
  echo "  PORTAINER_HOST : $PORTAINER_HOST"
  echo
  read -r -p "Os dados acima estão corretos? [S/n para re-editar]: " OK
  OK="${OK:-S}"
  [[ "$OK" =~ ^[sS]$ ]] && break
done

# Compose temporário do stack
TMP="/tmp/portainer-stack.yml"
log "Gerando stack em ${TMP}"
cat > "${TMP}" <<YML
version: "3.8"

services:
  agent:
    image: portainer/agent:2.21.4
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks: [ ${NETWORK_NAME} ]
    deploy:
      mode: global
      placement:
        constraints: [ node.platform.os == linux ]

  portainer:
    image: portainer/portainer-ce:2.21.4
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks: [ ${NETWORK_NAME} ]
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ node.role == manager ]
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=${NETWORK_NAME}"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_HOST}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  ${NETWORK_NAME}:
    external: true

volumes:
  portainer_data:
YML

# Deploy
log "Publicando stack 'portainer'"
docker stack deploy -c "${TMP}" portainer

# Esperar alguns segundos e validar
sleep 5
log "Status do serviço:"
docker service ps portainer_portainer || true

# Dicas finais
echo
log "Checklist pós-deploy:"
echo "  1) Garanta o A record na Cloudflare: ${PORTAINER_HOST} -> IP da VPS (DNS only recomendado no primeiro teste)"
echo "  2) Acesse: https://${PORTAINER_HOST}/"
echo "  3) Crie a senha do usuário admin na primeira abertura."
echo
log "Teste rápido via curl (pode mostrar HTML do login):"
curl -I "https://${PORTAINER_HOST}/" || true

log "Portainer publicado em: https://${PORTAINER_HOST} ✅"
