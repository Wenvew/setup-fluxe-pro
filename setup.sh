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
[2] Configurar Timezone (ex.: America/Sao_Paulo)
[3] Instalar Docker (repo oficial + daemon.json)
[4] Swarm & Rede (init + overlay)
[5] Traefik v3.0.4 (Swarm + Cloudflare DNS-01)
[6] Portainer (Swarm + Traefik)
[7] Ver log do painel
[0] Sair
MENU
  echo
  read -r -p "Escolha uma opção: " opt
  case "${opt:-}" in
    1) bash modules/01-update-only.sh    2>&1 | tee -a "$LOG_FILE";;
    2) bash modules/02-timezone.sh       2>&1 | tee -a "$LOG_FILE";;
    3) bash modules/03-docker.sh         2>&1 | tee -a "$LOG_FILE";;
    4) bash modules/04-swarm-network.sh  2>&1 | tee -a "$LOG_FILE";;
    5) bash modules/05-traefik.sh        2>&1 | tee -a "$LOG_FILE";;
    6) bash modules/06-portainer.sh      2>&1 | tee -a "$LOG_FILE";;
    7) ${PAGER:-less} "$LOG_FILE";;
    0) echo "Até mais!"; exit 0;;
    *) echo "Opção inválida."; sleep 1;;
  esac
}

while true; do main_menu; done
