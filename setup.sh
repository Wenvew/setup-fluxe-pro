#!/usr/bin/env bash
# setup.sh — Painel principal

set -Eeuo pipefail
cd "$(dirname "$0")"

. "lib/common.sh"
require_root
load_env

main_menu() {
  clear
  cat <<'MENU'
==========================================
   Painel de Setup — Fluxe (Terminal)
==========================================
[1] Atualizar VPS (somente apt update/upgrade)
[2] Instalar Traefik v3 (Swarm + Cloudflare)
[3] Instalar Portainer (via Traefik)
[4] Ver log do painel
[0] Sair
MENU
  echo
  read -r -p "Escolha uma opção: " opt
  case "${opt:-}" in
    1) bash modules/01-update-only.sh    2>&1 | tee -a "$LOG_FILE";;
    2) bash modules/02-install-traefik.sh  2>&1 | tee -a "$LOG_FILE";;
    3) bash modules/03-install-portainer.sh 2>&1 | tee -a "$LOG_FILE";;
    4) ${PAGER:-less} "$LOG_FILE";;
    0) echo "Até mais!"; exit 0;;
    *) echo "Opção inválida."; sleep 1;;
  esac
}

while true; do main_menu; done
