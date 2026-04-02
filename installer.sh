#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${ROOT_DIR}/lib/common.sh"
source "${ROOT_DIR}/installers/panel.sh"
source "${ROOT_DIR}/installers/wings.sh"

main() {
  parse_args "$@"
  require_root
  prompt_menu
  validate_inputs

  install_base_dependencies
  add_calagopus_repo
  prompt_db_password_if_needed

  if [[ "${ACTION}" == "panel" || "${ACTION}" == "both" ]]; then
    run_panel_install
  fi

  if [[ "${ACTION}" == "wings" || "${ACTION}" == "both" ]]; then
    run_wings_install
  fi

  print_finish_banner
}

main "$@"
