#!/usr/bin/env bash
# modules/01-update-only.sh — Atualiza a VPS (somente update/upgrade) e verifica resultado

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

log "Iniciando atualização da VPS (apt update && apt upgrade -y)"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y

log "Verificando pendências após upgrade"
PENDING=$(apt list --upgradable 2>/dev/null | grep -vc "Listing...") || true

# Informações úteis de saúde
KERNEL="$(uname -r)"
UPTIME="$(uptime -p || true)"

if [ "${PENDING:-0}" -gt 0 ]; then
  warn "Ainda há ${PENDING} pacote(s) atualizável(eis)."
  warn "Dica: rode novamente este módulo ou analise 'apt list --upgradable'."
else
  log "Sistema totalmente atualizado ✅"
fi

log "Kernel atual: ${KERNEL}"
log "Uptime: ${UPTIME}"
log "Finalizado."
