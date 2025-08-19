#!/usr/bin/env bash
# modules/02-timezone.sh — Configura o fuso horário da VPS

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

log "Configuração de Fuso Horário"
echo
echo "Escolha uma opção:"
echo "  [1] America/Sao_Paulo (recomendado para Brasil/SP)"
echo "  [2] Digitar outro timezone (formato IANA, ex.: America/Fortaleza)"
echo "  [0] Cancelar"
echo
read -r -p "Opção: " OPT

case "${OPT:-}" in
  1)
    TZ="America/Sao_Paulo"
    ;;
  2)
    read -r -p "Informe o timezone (ex.: America/Fortaleza): " TZ
    TZ="${TZ:-America/Sao_Paulo}"
    ;;
  0)
    warn "Operação cancelada pelo usuário."
    exit 0
    ;;
  *)
    warn "Opção inválida. Nada foi alterado."
    exit 1
    ;;
esac

log "Aplicando timezone: ${TZ}"
timedatectl set-timezone "${TZ}"

log "Verificando status do horário"
timedatectl status | sed -n '1,6p' || true

log "Fuso horário configurado para ${TZ} ✅"
