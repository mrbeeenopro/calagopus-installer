#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ACTION=""
PANEL_MODE=""
WITH_DB="yes"
PANEL_DIR="/opt/calagopus-panel"
PANEL_ENV_DIR="/etc/calagopus"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="panel"
DB_USER="calagopus"
DB_PASS=""
REDIS_URL="redis://localhost"

log() { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root (sudo)."
}

usage() {
  cat <<EOF
Calagopus Panel/Wings installer

Usage:
  sudo bash install.sh [options]

Options:
  --action <panel|wings|both>
  --panel-mode <docker|pkg>
  --with-db <yes|no>
  --panel-dir <path>
  --panel-env-dir <path>
  --db-host <host>
  --db-port <port>
  --db-name <name>
  --db-user <user>
  --db-pass <pass>
  --redis-url <url>
  -h, --help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action) ACTION="${2:-}"; shift 2 ;;
      --panel-mode) PANEL_MODE="${2:-}"; shift 2 ;;
      --with-db) WITH_DB="${2:-}"; shift 2 ;;
      --panel-dir) PANEL_DIR="${2:-}"; shift 2 ;;
      --panel-env-dir) PANEL_ENV_DIR="${2:-}"; shift 2 ;;
      --db-host) DB_HOST="${2:-}"; shift 2 ;;
      --db-port) DB_PORT="${2:-}"; shift 2 ;;
      --db-name) DB_NAME="${2:-}"; shift 2 ;;
      --db-user) DB_USER="${2:-}"; shift 2 ;;
      --db-pass) DB_PASS="${2:-}"; shift 2 ;;
      --redis-url) REDIS_URL="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

prompt_menu() {
  if [[ -z "${ACTION}" ]]; then
    echo "Select action:"
    echo "  1) Install panel"
    echo "  2) Install wings"
    echo "  3) Install both"
    read -r -p "Choice [1/2/3]: " ch
    case "${ch}" in
      1) ACTION="panel" ;;
      2) ACTION="wings" ;;
      3) ACTION="both" ;;
      *) die "Invalid action selection." ;;
    esac
  fi

  if [[ "${ACTION}" == "panel" || "${ACTION}" == "both" ]]; then
    if [[ -z "${PANEL_MODE}" ]]; then
      echo "Select panel install mode:"
      echo "  1) Docker"
      echo "  2) Package (APT)"
      read -r -p "Choice [1/2]: " ch
      case "${ch}" in
        1) PANEL_MODE="docker" ;;
        2) PANEL_MODE="pkg" ;;
        *) die "Invalid panel mode selection." ;;
      esac
    fi
  fi
}

validate_inputs() {
  [[ "${ACTION}" == "panel" || "${ACTION}" == "wings" || "${ACTION}" == "both" ]] || die "--action must be panel|wings|both"
  if [[ "${ACTION}" == "panel" || "${ACTION}" == "both" ]]; then
    [[ "${PANEL_MODE}" == "docker" || "${PANEL_MODE}" == "pkg" ]] || die "--panel-mode must be docker|pkg"
  fi
  [[ "${WITH_DB}" == "yes" || "${WITH_DB}" == "no" ]] || die "--with-db must be yes|no"
}

install_base_dependencies() {
  log "Installing base dependencies..."
  apt update
  apt install -y curl ca-certificates gnupg jq lsb-release postgresql-common
}

setup_calagopus_repo() {
  log "Adding Calagopus package repository..."
  curl -fsSL "https://packages.calagopus.com/pub.gpg" -o "/usr/share/keyrings/calagopus-archive-keyring.gpg"
  echo "deb [signed-by=/usr/share/keyrings/calagopus-archive-keyring.gpg] https://packages.calagopus.com/deb stable main" \
    | tee /etc/apt/sources.list.d/calagopus.list >/dev/null
  apt update
}

setup_postgresql_repo() {
  log "Adding PostgreSQL PGDG repository..."
  install -d /usr/share/postgresql-common/pgdg
  curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list
  apt update
}

prompt_db_password_if_needed() {
  if [[ "${WITH_DB}" == "yes" && -z "${DB_PASS}" ]]; then
    read -r -s -p "PostgreSQL password for user '${DB_USER}': " DB_PASS
    printf "\n"
  fi
}

escape_sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

random_key() {
  tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32
}

install_docker_runtime() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already present."
  else
    log "Installing Docker runtime..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
  fi
  systemctl enable --now docker
}

write_panel_env() {
  local env_file="$1"
  local key
  key="$(random_key)"

  mkdir -p "$(dirname "${env_file}")"
  cat > "${env_file}" <<EOF
DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
REDIS_URL="${REDIS_URL}"
APP_ENCRYPTION_KEY="${key}"
PORT=8000
EOF
  chmod 600 "${env_file}"
  log "Environment written to ${env_file}"
}

print_finish_banner() {
  echo
  echo "========================================="
  echo " Calagopus installation finished"
  echo "========================================="
  echo "- Action: ${ACTION}"
  if [[ "${ACTION}" == "panel" || "${ACTION}" == "both" ]]; then
    echo "- Panel mode: ${PANEL_MODE}"
    echo "- Panel URL: http://<server-ip>:8000"
  fi
  if [[ "${ACTION}" == "wings" || "${ACTION}" == "both" ]]; then
    echo "- Wings next step:"
    echo "  calagopus-wings configure --join-data <token>"
  fi
}
