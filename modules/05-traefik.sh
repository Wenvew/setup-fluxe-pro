#!/usr/bin/env bash
# modules/05-traefik.sh — Traefik v3.0.4 via template (envsubst)

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia — Traefik v3 no Swarm (Cloudflare DNS-01)
Pré: Docker [3], Swarm+Rede [4], domínio na Cloudflare e token (Zone:Read + DNS:Edit).
GUIDE
echo

# Checagens
docker info >/dev/null || die "Docker não está rodando."
[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ] || die "Swarm não está ativo."

# Coleta + revisão
while true; do
  prompt_var DOMAIN        "Domínio raiz" "${DOMAIN:-fluxe.one}"
  prompt_var TRAEFIK_HOST  "Host do dashboard (FQDN)" "${TRAEFIK_HOST:-traefik.${DOMAIN}}"
  prompt_var ACME_EMAIL    "E-mail ACME (Let's Encrypt)" "${ACME_EMAIL:-infra@${DOMAIN}}"
  prompt_var NETWORK_NAME  "Rede overlay (já existente)" "${NETWORK_NAME:-network_public}"
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || die "Rede '$NETWORK_NAME' não existe (rode o módulo [4])."
  prompt_var   DASH_USER   "Usuário do dashboard" "${DASH_USER:-superadmin}"
  prompt_secret DASH_PWD   "Senha do dashboard"
  prompt_secret CF_API_TOKEN "Cloudflare API Token"

  echo
  echo "Resumo:"
  echo "  DOMAIN       : $DOMAIN"
  echo "  TRAEFIK_HOST : $TRAEFIK_HOST"
  echo "  ACME_EMAIL   : $ACME_EMAIL"
  echo "  NETWORK_NAME : $NETWORK_NAME"
  echo "  DASH_USER    : $DASH_USER"
  echo "  DASH_PWD     : ********"
  echo "  CF_API_TOKEN : ********"
  read -r -p "Confirmar e continuar? [S/n]: " OK; OK="${OK:-S}"
  [[ "$OK" =~ ^[sS]$ ]] && break
done

# Estrutura + secrets/configs
install -d -m 0750 /srv/infra/traefik/{acme,logs}
install -d -m 0700 /srv/infra/traefik/.secrets

log "Criando secret da Cloudflare"
printf "%s" "$CF_API_TOKEN" | tr -d '\r\n' > /srv/infra/traefik/.secrets/cf_token.txt
chmod 0400 /srv/infra/traefik/.secrets/cf_token.txt
docker secret rm cf_token_v2 2>/dev/null || true
docker secret create cf_token_v2 /srv/infra/traefik/.secrets/cf_token.txt

log "Criando usersfile (BasicAuth)"
docker run --rm httpd:2.4-alpine htpasswd -nbB "$DASH_USER" "$DASH_PWD" > /srv/infra/traefik/usersfile
grep -v '^[[:space:]]*$' /srv/infra/traefik/usersfile | head -n1 > /srv/infra/traefik/usersfile.clean && mv /srv/infra/traefik/usersfile.clean /srv/infra/traefik/usersfile
chmod 0400 /srv/infra/traefik/usersfile

# Render do template
command -v envsubst >/dev/null || (apt update && apt install -y gettext-base)
export ACME_EMAIL TRAEFIK_HOST NETWORK_NAME
STACK_OUT="/srv/infra/traefik/traefik-stack.yml"
log "Renderizando template templates/traefik-stack.yml.tpl -> ${STACK_OUT}"
envsubst < templates/traefik-stack.yml.tpl > "${STACK_OUT}"

# Validar e publicar
log "Validando YAML"
docker compose -f "${STACK_OUT}" config >/dev/null && log "YAML OK"

log "Deploy stack 'traefik'"
docker stack deploy -c "${STACK_OUT}" traefik

log "Acompanhar ACME/DNS por 40s..."
timeout 40s bash -c 'docker service logs -f --since 2m traefik_traefik | egrep -Ei "acme|letsencrypt|dns|challenge|certificate|error|warn" || true'

log "Testes rápidos"
curl -I "http://${TRAEFIK_HOST}" || true
curl -I "https://${TRAEFIK_HOST}/dashboard/" || true
echo "(com BasicAuth)"
curl -s -u "${DASH_USER}:${DASH_PWD}" "https://${TRAEFIK_HOST}/dashboard/" | head -n 3 || true

log "OK: Traefik em https://${TRAEFIK_HOST}/dashboard/ ✅"
