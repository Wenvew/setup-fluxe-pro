#!/usr/bin/env bash
# modules/05-traefik.sh — Instala Traefik v3.0.4 no Swarm com ACME DNS-01 (Cloudflare)
# Fluxo: guia -> coleta -> revisão -> confirmação -> deploy -> verificação

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia rápido — Traefik v3 no Swarm (com Cloudflare DNS-01)
1) Pré-requisitos:
   • Docker instalado (use o módulo [3]).
   • Swarm ativo + rede overlay criada (use o módulo [4]).
   • Domínio gerenciado na Cloudflare.
   • Token Cloudflare com permissões: Zone:Read + DNS:Edit.

2) O que vou te pedir:
   • DOMAIN (ex.: fluxe.one)
   • TRAEFIK_HOST (ex.: traefik.fluxe.one)
   • ACME_EMAIL (e-mail para Let's Encrypt)
   • NETWORK_NAME (ex.: network_public)
   • DASH_USER e DASH_PWD (acesso ao dashboard)
   • CF_API_TOKEN (será guardado como Docker Secret)

3) Resultado:
   • Stack "traefik" publicada com HTTPS automático (DNS-01).
   • Dashboard em https://TRAEFIK_HOST/dashboard/ (com BasicAuth).
GUIDE
echo

# --- Checagens iniciais ---
if ! docker info >/dev/null 2>&1; then
  die "Docker não está instalado/rodando. Rode primeiro o módulo [3] Instalar Docker."
fi
SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
[ "$SWARM_STATE" = "active" ] || die "Swarm não está ativo. Rode o módulo [4] Swarm & Rede."

# --- Coleta + revisão/edição com confirmação ---
while true; do
  prompt_var DOMAIN        "Domínio raiz (gerenciado na Cloudflare)" "${DOMAIN:-fluxe.one}"
  DEFAULT_HOST="${TRAEFIK_HOST:-traefik.${DOMAIN}}"
  prompt_var TRAEFIK_HOST  "Host do dashboard (FQDN)" "${DEFAULT_HOST}"
  prompt_var ACME_EMAIL    "E-mail para o Let's Encrypt (ACME)" "${ACME_EMAIL:-infra@${DOMAIN}}"

  # Rede overlay (precisa existir)
  prompt_var NETWORK_NAME  "Nome da rede overlay (já criada no módulo [4])" "${NETWORK_NAME:-network_public}"
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    err "Rede '$NETWORK_NAME' não existe. Rode o módulo [4] e tente novamente."
    exit 1
  fi

  prompt_var DASH_USER     "Usuário para o dashboard" "${DASH_USER:-superadmin}"
  prompt_secret DASH_PWD   "Senha do dashboard (não aparece ao digitar)"
  prompt_secret CF_API_TOKEN "Cloudflare API Token (Zone:Read + DNS:Edit)"

  echo
  echo "Resumo dos dados:"
  echo "  DOMAIN       : $DOMAIN"
  echo "  TRAEFIK_HOST : $TRAEFIK_HOST"
  echo "  ACME_EMAIL   : $ACME_EMAIL"
  echo "  NETWORK_NAME : $NETWORK_NAME"
  echo "  DASH_USER    : $DASH_USER"
  echo "  DASH_PWD     : ********"
  echo "  CF_API_TOKEN : ********"
  echo
  read -r -p "Os dados acima estão corretos? [S/n para re-editar]: " OK
  OK="${OK:-S}"
  [[ "$OK" =~ ^[sS]$ ]] && break
done

# --- Estrutura de pastas ---
log "Criando estrutura do Traefik em /srv/infra/traefik"
install -d -m 0750 /srv/infra/traefik/{acme,logs}
install -d -m 0700 /srv/infra/traefik/.secrets

# --- Secret Cloudflare (como arquivo) ---
log "Criando Docker Secret com o token da Cloudflare"
printf "%s" "$CF_API_TOKEN" | tr -d '\r\n' > /srv/infra/traefik/.secrets/cf_token.txt
chmod 0400 /srv/infra/traefik/.secrets/cf_token.txt
docker secret rm cf_token_v2 2>/dev/null || true
docker secret create cf_token_v2 /srv/infra/traefik/.secrets/cf_token.txt

# --- BasicAuth (usersfile) ---
log "Gerando usersfile (BasicAuth) para o dashboard"
docker run --rm httpd:2.4-alpine htpasswd -nbB "$DASH_USER" "$DASH_PWD" > /srv/infra/traefik/usersfile
grep -v '^[[:space:]]*$' /srv/infra/traefik/usersfile | head -n1 > /srv/infra/traefik/usersfile.clean && mv /srv/infra/traefik/usersfile.clean /srv/infra/traefik/usersfile
chmod 0400 /srv/infra/traefik/usersfile

# --- Gerar stack do Traefik ---
STACK="/srv/infra/traefik/traefik-stack.yml"
log "Escrevendo stack do Traefik em ${STACK}"
cat > "${STACK}" <<YML
version: "3.8"

services:
  traefik:
    image: traefik:3.0.4
    command:
      - "--providers.swarm=true"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=${NETWORK_NAME}"

      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"

      # ACME (Cloudflare DNS-01)
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.delaybeforecheck=0"

      # Dashboard + logs
      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--log.level=INFO"

      # Access log (JSON) + privacidade de headers
      - "--accesslog=true"
      - "--accesslog.format=json"
      - "--accesslog.filepath=/logs/access.log"
      - "--accesslog.fields.headers.defaultmode=drop"
      - "--accesslog.fields.headers.names.User-Agent=keep"
      - "--accesslog.fields.headers.names.X-Forwarded-For=keep"
      - "--accesslog.fields.headers.names.Authorization=redact"

    ports:
      - "80:80"
      - "443:443"

    networks:
      - ${NETWORK_NAME}

    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "/srv/infra/traefik/acme:/letsencrypt"
      - "/srv/infra/traefik/logs:/logs"

    # DNS-01 via secret de arquivo
    secrets:
      - cf_token_v2
    environment:
      - CF_DNS_API_TOKEN_FILE=/run/secrets/cf_token_v2

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [ "node.role == manager" ]
      labels:
        - "traefik.enable=true"
        - "traefik.http.services.traefik.loadbalancer.server.port=80"

        # Dashboard em ${TRAEFIK_HOST}
        - "traefik.http.routers.traefik.rule=Host(\`${TRAEFIK_HOST}\`)"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
        - "traefik.http.routers.traefik.service=api@internal"

        # BasicAuth via usersfile (Docker config)
        - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/usersfile"
        - "traefik.http.routers.traefik.middlewares=dashboard-auth@swarm"

    configs:
      - source: traefik_usersfile
        target: /usersfile
        mode: 0400

networks:
  ${NETWORK_NAME}:
    external: true

secrets:
  cf_token_v2:
    external: true

configs:
  traefik_usersfile:
    file: /srv/infra/traefik/usersfile
YML

# --- Validar e publicar ---
log "Validando YAML do stack"
docker compose -f "${STACK}" config >/dev/null && log "YAML OK"

log "Publicando stack 'traefik'"
docker stack deploy -c "${STACK}" traefik

# --- Acompanhar emissão de certificado ---
log "Acompanhando logs (ACME/DNS) por 40s..."
timeout 40s bash -c 'docker service logs -f --since 2m traefik_traefik | egrep -Ei "acme|letsencrypt|dns|challenge|certificate|error|warn" || true'

# --- Testes rápidos ---
log "Testes HTTP/HTTPS"
curl -I "http://${TRAEFIK_HOST}" || true
curl -I "https://${TRAEFIK_HOST}/dashboard/" || true
echo "(HEAD geralmente responde 401. Tentando GET com BasicAuth...)"
curl -s -u "${DASH_USER}:${DASH_PWD}" "https://${TRAEFIK_HOST}/dashboard/" | head -n 3 || true

log "Concluído. Traefik v3 publicado em: https://${TRAEFIK_HOST}/dashboard/ ✅"
