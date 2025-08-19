#!/usr/bin/env bash
# modules/06-portainer.sh — Portainer via template (envsubst) com opção de admin pré-definido

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia — Portainer no Swarm (via Traefik)
Pré: Docker [3], Swarm+Rede [4]. Com Traefik [5], terá TLS automático com DNS-01.

• Você pode deixar o Portainer criar a senha do admin na UI (primeiro acesso), ou
• Pré-definir a senha agora (hash bcrypt em Docker Secret, mais seguro e automático).
GUIDE
echo

docker info >/dev/null || die "Docker não está rodando."
[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ] || die "Swarm não está ativo ([4])."

# Coleta + revisão
while true; do
  prompt_var NETWORK_NAME   "Rede overlay (já existente)" "${NETWORK_NAME:-network_public}"
  docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || die "Rede '$NETWORK_NAME' não existe."
  prompt_var PORTAINER_HOST "Host do Portainer (FQDN)" "${PORTAINER_HOST:-portainer.${DOMAIN:-fluxe.one}}"

  # Escolha sobre senha do admin
  read -r -p "Deseja pré-definir a senha do admin? [s/N]: " PREDEF
  PREDEF="${PREDEF:-N}"

  PORTAINER_ADMIN_PASSWORD_FLAG=""
  PORTAINER_ADMIN_SECRET_BLOCK=""
  PORTAINER_SECRETS_DEF_BLOCK=""

  if [[ "$PREDEF" =~ ^[sS]$ ]]; then
    # pedir senha + confirmação
    prompt_secret ADMIN_PWD_1 "Digite a senha do admin (não aparece)"
    prompt_secret ADMIN_PWD_2 "Confirme a senha do admin"
    if [ "$ADMIN_PWD_1" != "$ADMIN_PWD_2" ]; then
      err "As senhas não conferem. Tente novamente."
      continue
    fi

    # gerar hash bcrypt usando httpd:2.4-alpine (htpasswd)
    log "Gerando hash bcrypt da senha (httpd:2.4-alpine)"
    HASH="$(docker run --rm httpd:2.4-alpine htpasswd -nbB admin "$ADMIN_PWD_1" | cut -d: -f2)"
    [ -n "$HASH" ] || die "Falha ao gerar hash."

    # criar/atualizar secret
    SECRET_NAME="portainer_admin_hash"
    echo -n "$HASH" > /tmp/portainer_admin_hash
    docker secret rm "$SECRET_NAME" 2>/dev/null || true
    docker secret create "$SECRET_NAME" /tmp/portainer_admin_hash
    rm -f /tmp/portainer_admin_hash

    # preparar placeholders para o template
    PORTAINER_ADMIN_PASSWORD_FLAG="--admin-password-file /run/secrets/${SECRET_NAME}"
    read -r -d '' PORTAINER_ADMIN_SECRET_BLOCK <<'YAML' || true
    secrets:
      - portainer_admin_hash
YAML
    read -r -d '' PORTAINER_SECRETS_DEF_BLOCK <<'YAML' || true
secrets:
  portainer_admin_hash:
    external: true
YAML
  fi

  echo
  echo "Resumo:"
  echo "  NETWORK_NAME                : $NETWORK_NAME"
  echo "  PORTAINER_HOST              : $PORTAINER_HOST"
  if [[ "$PREDEF" =~ ^[sS]$ ]]; then
    echo "  Admin pré-definido         : SIM (via secret 'portainer_admin_hash')"
  else
    echo "  Admin pré-definido         : NÃO (definir na UI no primeiro acesso)"
  fi
  read -r -p "Confirmar e continuar? [S/n]: " OK; OK="${OK:-S}"
  [[ "$OK" =~ ^[sS]$ ]] && break
done

command -v envsubst >/dev/null || (apt update && apt install -y gettext-base)
export NETWORK_NAME PORTAINER_HOST PORTAINER_ADMIN_PASSWORD_FLAG PORTAINER_ADMIN_SECRET_BLOCK PORTAINER_SECRETS_DEF_BLOCK

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
echo "  2) Acesse: https://${PORTAINER_HOST}/"
if [[ "$PREDEF" =~ ^[sS]$ ]]; then
  echo "  • Usuário: admin  (senha definida por você; guardada como secret)"
else
  echo "  • Na primeira abertura, o Portainer pedirá para criar a senha do admin."
fi
echo
log "Teste rápido:"
curl -I "https://${PORTAINER_HOST}/" || true

log "OK: Portainer publicado em https://${PORTAINER_HOST} ✅"
