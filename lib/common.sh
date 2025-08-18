# lib/common.sh — Funções utilitárias compartilhadas

set -Eeuo pipefail

LOG_FILE="/var/log/setup-fluxe-pro.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log()   { echo -e "[\e[32mOK\e[0m] $*";   echo "[OK] $*"   >> "$LOG_FILE"; }
warn()  { echo -e "[\e[33mWARN\e[0m] $*"; echo "[WARN] $*" >> "$LOG_FILE"; }
err()   { echo -e "[\e[31mERR\e[0m] $*"  >&2; echo "[ERR] $*"  >> "$LOG_FILE"; }
die()   { err "$*"; exit 1; }

require_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root."; }

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Comando obrigatório ausente: $c"
  done
}

# Carrega .env (se existir)
load_env() {
  if [ -f ".env" ]; then
    # shellcheck disable=SC2046
    export $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | cut -d= -f1)
    set -a; . ./.env; set +a
    log "Variáveis do .env carregadas."
  else
    warn ".env não encontrado. Será criado no primeiro uso."
  fi
}

# Salva/atualiza a variável no .env
save_env_var() {
  local key="$1" val="$2"
  touch .env
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" .env
  else
    printf '%s="%s"\n' "$key" "$val" >> .env
  fi
}

prompt_var() {
  local key="$1" msg="$2" default="${3:-}"
  local current="${!key:-}"
  if [ -n "${current:-}" ]; then
    echo "$key detectado no ambiente: $current"
    read -r -p "$msg [Enter p/ manter: ${current}] " val || true
    val="${val:-$current}"
  else
    if [ -n "$default" ]; then
      read -r -p "$msg [Default: $default]: " val || true
      val="${val:-$default}"
    else
      read -r -p "$msg: " val || true
    fi
  fi
  export "$key"="$val"
  save_env_var "$key" "$val"
}

prompt_secret() {
  local key="$1" msg="$2"
  local current="${!key:-}"
  if [ -n "${current:-}" ]; then
    read -r -p "$msg [Enter p/ manter segredo já salvo]: " tmp || true
    if [ -n "${tmp:-}" ]; then
      export "$key"="$tmp"
      save_env_var "$key" "$tmp"
    fi
  else
    read -rsp "$msg: " val || true; echo
    export "$key"="$val"
    save_env_var "$key" "$val"
  fi
}

detect_pubip() {
  ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
}
