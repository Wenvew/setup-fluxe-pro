#!/usr/bin/env bash
# modules/04-swarm-network.sh — Inicializa Docker Swarm e cria rede overlay (com guia didático na tela)

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root
require_cmd docker

clear
cat <<'GUIDE'
🔰 Guia rápido — o que escolher aqui (seguro para iniciantes)

1) Nome da rede overlay:
   • Use "network_public" (padrão recomendado). É a rede onde Traefik/serviços vão publicar.

2) Ajustes de kernel (br_netfilter + ip_forward):
   • Responda "S" (Sim). Isso habilita recursos de rede necessários para Swarm/overlay.

3) advertise-addr (endereço de anúncio do Swarm):
   • Aceite o IP detectado (geralmente é o IP público da VPS).
   • Se vier vazio, digite manualmente o IP público da sua VPS.

4) Confirmação:
   • Revise o resumo e digite "S" para prosseguir.

💡 Este módulo é idempotente: se o Swarm já estiver ativo ou a rede já existir, nada será recriado.
GUIDE
echo

# Checagem básica do Docker
if ! docker info >/dev/null 2>&1; then
  die "Docker não está instalado/rodando. Rode primeiro o módulo [3] Instalar Docker."
fi

# --- Coleta de parâmetros (com persistência em .env) ---
prompt_var NETWORK_NAME "Nome da rede overlay (onde os serviços serão publicados)" "${NETWORK_NAME:-network_public}"

echo
read -r -p "Aplicar ajustes de kernel (br_netfilter + ip_forward)? [S/n]: " KOPT
KOPT="${KOPT:-S}"
if [[ "$KOPT" =~ ^[sS]$ ]]; then APPLY_KERNEL="yes"; else APPLY_KERNEL="no"; fi
save_env_var APPLY_KERNEL "$APPLY_KERNEL"

DETECTED="$(detect_pubip || true)"
DEFAULT_ADVERTISE="${ADVERTISE_ADDR:-${DETECTED:-}}"
prompt_var ADVERTISE_ADDR "Endereço IP para advertise-addr do Swarm (geralmente o IP público)" "${DEFAULT_ADVERTISE}"

# --- Resumo antes de aplicar ---
state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
echo
echo "Resumo da operação:"
echo "  - Aplicar ajustes de kernel : ${APPLY_KERNEL}"
echo "  - advertise-addr            : ${ADVERTISE_ADDR}"
echo "  - Nome da rede overlay      : ${NETWORK_NAME}"
echo "  - Estado atual do Swarm     : ${state:-desconhecido}"
echo
read -r -p "Confirmar e continuar? [S/n]: " CONF
CONF="${CONF:-S}"
if [[ ! "$CONF" =~ ^[sS]$ ]]; then
  warn "Operação cancelada pelo usuário."
  exit 0
fi

# --- Aplicação ---
if [ "$APPLY_KERNEL" = "yes" ]; then
  log "Aplicando ajustes de kernel (br_netfilter, iptables bridge e ip_forward)"
  modprobe br_netfilter || true
  cat >/etc/sysctl.d/99-swarm-overlays.conf <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
  sysctl --system >/dev/null || true
else
  warn "Pulando ajustes de kernel a pedido do usuário."
fi

if [ "$state" != "active" ]; then
  log "Inicializando Docker Swarm com advertise-addr ${ADVERTISE_ADDR}"
  docker swarm init --advertise-addr "$ADVERTISE_ADDR"
else
  log "Swarm já está ativo — pulando 'swarm init'."
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  warn "Rede '${NETWORK_NAME}' já existe — mantendo."
else
  log "Criando rede overlay '${NETWORK_NAME}' (attachable)"
  docker network create --driver overlay --attachable "$NETWORK_NAME"
fi

log "Status do Swarm:"
docker info --format ' Swarm: {{.Swarm.LocalNodeState}} | NodeID: {{.Swarm.NodeID}}' || true

log "Redes overlay existentes:"
docker network ls --filter driver=overlay || true

log "Swarm & rede configurados ✅"
