#!/usr/bin/env bash
# modules/03-install-portainer.sh — Instala Portainer e roteia via Traefik

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

prompt_var DOMAIN "Informe o seu domínio raiz" "${DOMAIN:-fluxe.one}"
prompt_var PORTAINER_HOST "Host do Portainer" "${PORTAINER_HOST:-portainer.${DOMAIN}}"

# Verificações básicas
docker info >/dev/null 2>&1 || die "Docker não está instalado/rodando."
state="$(docker info --format '{{.Swarm.LocalNodeState}}')"
[ "$state" = "active" ] || die "Swarm não inicializado. Rode o módulo do Traefik antes."

docker network inspect network_public >/dev/null 2>&1 || die "network_public não existe. Rode o módulo do Traefik antes."

log "Criando stack do Portainer"
cat >/tmp/portainer-stack.yml <<YML
version: "3.8"

services:
  agent:
    image: portainer/agent:2.21.4
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks: [ network_public ]
    deploy:
      mode: global
      placement:
        constraints: [ node.platform.os == linux ]

  portainer:
    image: portainer/portainer-ce:2.21.4
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks: [ network_public ]
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ node.role == manager ]
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=network_public"
        - "traefik.http.routers.portainer.rule=Host(`${PORTAINER_HOST}`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  network_public:
    external: true

volumes:
  portainer_data:
YML

docker stack deploy -c /tmp/portainer-stack.yml portainer
log "Portainer publicado em: https://${PORTAINER_HOST}"
