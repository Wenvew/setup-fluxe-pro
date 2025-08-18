#!/usr/bin/env bash
# modules/01-system-update.sh — Atualiza VPS e configura DNS do host

set -Eeuo pipefail
cd "$(dirname "$0")/.."
. "lib/common.sh"
require_root

log "Atualizando sistema e instalando utilitários"
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg lsb-release jq bind9-dnsutils

log "Configurando systemd-resolved com Cloudflare + fallbacks (persistente)"
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/99-cloudflare-google.conf <<'CONF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 9.9.9.9
DNSSEC=no
CONF
systemctl enable --now systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

log "Testando resolução DNS no host"
dig +short acme-v02.api.letsencrypt.org || warn "Falha em resolver ACME; verifique firewall/DO"
log "Concluído."
