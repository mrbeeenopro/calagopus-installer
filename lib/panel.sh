#!/usr/bin/env bash
set -euo pipefail

run_panel_install() {
  if [[ "${WITH_DB}" == "yes" ]]; then
    install_database_stack
    setup_database
  else
    warn "Skipping DB install/setup (--with-db=no)."
    warn "Ensure PostgreSQL and Valkey/Redis are running and reachable."
  fi

  if [[ "${PANEL_MODE}" == "docker" ]]; then
    install_panel_docker
  else
    install_panel_pkg
  fi
}

install_database_stack() {
  log "Installing PostgreSQL + Valkey..."
  setup_postgresql_repo
  apt install -y postgresql-18 valkey
  systemctl enable --now postgresql
  systemctl enable --now valkey-server || systemctl enable --now valkey
}

setup_database() {
  [[ -n "${DB_PASS}" ]] || die "DB password cannot be empty when --with-db=yes"
  local safe_pass
  safe_pass="$(escape_sql_literal "${DB_PASS}")"

  log "Creating/updating PostgreSQL user and database..."
  sudo -u postgres psql <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE USER ${DB_USER} WITH PASSWORD '${safe_pass}';
   ELSE
      ALTER USER ${DB_USER} WITH PASSWORD '${safe_pass}';
   END IF;
END
\$\$;
SQL

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
  else
    sudo -u postgres psql -c "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"
  fi
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
}

install_panel_docker() {
  log "Installing Calagopus Panel (Docker mode)..."
  install_docker_runtime
  mkdir -p "${PANEL_DIR}"
  curl -fsSL "https://raw.githubusercontent.com/calagopus/panel/refs/heads/main/compose.yml" -o "${PANEL_DIR}/compose.yml"
  write_panel_env "${PANEL_DIR}/.env"

  (
    cd "${PANEL_DIR}"
    if docker compose version >/dev/null 2>&1; then
      docker compose up -d
    else
      apt install -y docker-compose
      docker-compose up -d
    fi
  )
}

install_panel_pkg() {
  log "Installing Calagopus Panel (APT mode)..."
  apt install -y calagopus-panel
  mkdir -p "${PANEL_ENV_DIR}"
  write_panel_env "${PANEL_ENV_DIR}/.env"
  calagopus-panel service-install || true
  systemctl enable --now calagopus-panel || true
}
