#!/usr/bin/env bash
set -euo pipefail

run_wings_install() {
  log "Installing Calagopus Wings..."
  apt install -y calagopus-wings
  if ! command -v wings >/dev/null 2>&1 && command -v calagopus-wings >/dev/null 2>&1; then
    ln -sf "$(command -v calagopus-wings)" /usr/local/bin/wings
  fi
}
