#!/usr/bin/env bash
# modules/00-full-setup.sh — Orquestra a instalação completa (1 → 6)
# Fluxo: guia -> coleta -> resumo -> confirmação -> executa módulos 1..6

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

clear
cat <<'GUIDE'
🔰 Guia — Instalação completa (1 → 6)
Este assistente vai:
  1) Atualizar a VPS
  2) (Opcional) Configurar o fuso horário
  3) Instalar Docker (repo oficial) + daemon.json (DNS/logs/BuildKit)
  4) Inicializar Swarm e criar rede overlay
  5) Instalar Traefik v3 (ACME DNS-01 via Cloudflare) com dashboard protegido
  6) Instalar Portainer (via Traefik)

Você informará os dados uma vez; mostraremos um RESUMO antes de aplicar.
Durante cada etapa, os módulos podem exibir prompts já preenchidos — basta pressionar Enter para aceitar.
GUIDE
echo

# ---------- Coleta dos dados ----------
# 2) Timezone
read -r -p "Configurar timezone agora? [S/n] (recomendado): " DO_TZ
DO_TZ="${DO_TZ:-S}"
if [[ "$DO_TZ" =~ ^[sS]$ ]]; then
  # padrão sugerido
  TZ_CHOSEN="${TZ_CHOSEN:-America/Sao_Paulo}"
  read -r -p "Informe o timezone (padrão America/Sao_Paulo): " TMP_TZ
  TZ_CHOSEN="${TMP_TZ:-$TZ_CHOSEN}"
fi

# 4) Swarm & Rede
prompt_var NETWORK_NAME "Nome da rede overlay" "${NETWORK_NAME:-network_public}"
read -r -p "Aplicar ajustes de kernel (br_netfilter/ip_forward)? [S/n]: " KOPT
KOPT="${KOPT:-S}"
APPLY_KERNEL=$([[ "$KOPT" =~ ^[sS]$ ]] && echo "yes" || echo "no")
DETECTED="$(detect_pubip || true)"
DEFAULT_ADVERTISE="${ADVERTISE_ADDR:-${DETECTED:-}}"
prompt_var ADVERTISE_ADDR "advertise-addr do Swarm (IP público)" "${DEFAULT_ADVERTISE}"

# 5) Traefik
prompt_var DOMAIN        "Domínio raiz (na Cloudflare)" "${DOMAIN:-fluxe.one}"
prompt_var TRAEFIK_HOST  "Host do dashboard (FQDN)"     "${TRAEFIK_HOST:-traefik.${DOMAIN}}"
prompt_var ACME_EMAIL    "E-mail do Let's Encrypt"      "${ACME_EMAIL:-infra@${DOMAIN}}"
prompt_var DASH_USER     "Usuário do dashboard"         "${DASH_USER:-superadmin}"
prompt_secret DASH_PWD   "Senha do dashboard"
prompt_secret CF_API_TOKEN "Cloudflare API Token (Zone:Read + DNS:Edit)"

# 6) Portainer
DEFAULT_PORTAINER_HOST="${PORTAINER_HOST:-portainer.${DOMAIN}}"
prompt_var PORTAINER_HOST "Host do Portainer (FQDN)" "${DEFAULT_PORTAINER_HOST}"

# ---------- Resumo ----------
echo
echo "Resumo para revisão:"
echo "  Timezone           : ${DO_TZ^^} $( [[ "$DO_TZ" =~ ^[sS]$ ]] && echo "→ $TZ_CHOSEN" || echo "(pular)" )"
echo "  Rede overlay       : ${NETWORK_NAME}"
echo "  Ajustes de kernel  : ${APPLY_KERNEL}"
echo "  advertise-addr     : ${ADVERTISE_ADDR}"
echo "  Traefik DOMAIN     : ${DOMAIN}"
echo "  Traefik HOST       : ${TRAEFIK_HOST}"
echo "  ACME e-mail        : ${ACME_EMAIL}"
echo "  Dashboard user     : ${DASH_USER}"
echo "  Dashboard senha    : ********"
echo "  Cloudflare token   : ********"
echo "  Portainer HOST     : ${PORTAINER_HOST}"
echo
read -r -p "Confirmar e executar TUDO em sequência (1→6)? [S/n]: " OK
OK="${OK:-S}"
if [[ ! "$OK" =~ ^[sS]$ ]]; then
  warn "Instalação completa cancelada pelo usuário."
  exit 0
fi

# ---------- Exporta variáveis para os módulos ----------
export TZ_CHOSEN NETWORK_NAME APPLY_KERNEL ADVERTISE_ADDR
export DOMAIN TRAEFIK_HOST ACME_EMAIL DASH_USER DASH_PWD CF_API_TOKEN
export PORTAINER_HOST
save_env_var NETWORK_NAME "$NETWORK_NAME" || true
save_env_var DOMAIN "$DOMAIN" || true
save_env_var TRAEFIK_HOST "$TRAEFIK_HOST" || true
save_env_var ACME_EMAIL "$ACME_EMAIL" || true
save_env_var DASH_USER "$DASH_USER" || true
save_env_var PORTAINER_HOST "$PORTAINER_HOST" || true

# ---------- Execução em sequência ----------
run_step() {
  local title="$1"; shift
  log "==> ${title}"
  # executa comando e encadeia log do painel
  ( "$@" ) 2>&1 | tee -a "$LOG_FILE"
}

# 1) Update only
run_step "1/6 Atualizando VPS" bash modules/01-update-only.sh

# 2) Timezone (se escolhido)
if [[ "$DO_TZ" =~ ^[sS]$ ]]; then
  # módulo 02 tem menu interativo (1 = America/Sao_Paulo / 2 = digitar).
  if [[ "$TZ_CHOSEN" == "America/Sao_Paulo" ]]; then
    # escolhe opção 1 automaticamente
    run_step "2/6 Configurando timezone (America/Sao_Paulo)" bash -lc 'printf "1\n" | bash modules/02-timezone.sh'
  else
    # usa fluxo "2 = digitar outro timezone"
    run_step "2/6 Configurando timezone ($TZ_CHOSEN)" bash -lc 'printf "2\n%s\n" "$TZ_CHOSEN" | bash modules/02-timezone.sh'
  fi
else
  warn "2/6 Timezone pulado a pedido do usuário."
fi

# 3) Docker
run_step "3/6 Instalando Docker" bash modules/03-docker.sh

# 4) Swarm & Rede (vai mostrar prompts já preenchidos)
# como o módulo 04 ainda pede confirmação, só aperte Enter para aceitar os defaults
run_step "4/6 Swarm & Rede (init + overlay)" bash modules/04-swarm-network.sh

# 5) Traefik (usar variáveis exportadas; confirme o resumo com 'S')
run_step "5/6 Traefik v3 (Swarm + Cloudflare DNS-01)" bash modules/05-traefik.sh

# 6) Portainer
run_step "6/6 Portainer (via Traefik)" bash modules/06-portainer.sh

echo
log "Instalação completa finalizada ✅"
echo "Acesse:"
echo "  • Traefik:   https://${TRAEFIK_HOST}/dashboard/"
echo "  • Portainer: https://${PORTAINER_HOST}/"
