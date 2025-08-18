#!/usr/bin/env bash
# Uso:
#   ./install-remote.sh root@IP_DA_VPS
# Ex.: ./install-remote.sh root@143.198.xxx.xxx

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 usuario@IP"
  exit 1
fi

TARGET="$1"

ssh -o StrictHostKeyChecking=accept-new "$TARGET" 'bash -s' <<'EOF'
set -euo pipefail
apt update && apt install -y git curl unzip || true

cd /root
rm -rf setup-fluxe-pro
git clone https://github.com/Wenvew/setup-fluxe-pro.git
cd setup-fluxe-pro

chmod +x setup.sh modules/*.sh
echo "=========================================="
echo " Painel pronto. Para iniciar, rode: ./setup.sh"
echo "=========================================="
./setup.sh
EOF
