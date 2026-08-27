#!/usr/bin/env bash
# Shared helpers. Source this from every script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"

set -euo pipefail

# --- logging ----------------------------------------------------------------
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"

log()   { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $*"; }
warn()  { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"; }
die()   { echo -e "${COLOR_RED}[x]${COLOR_RESET} $*" >&2; exit 1; }

# --- checks -------------------------------------------------------------
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
  fi
}

# Ask a yes/no question. Returns 0 for yes, 1 for no.
# Usage: if confirm "Continue?"; then ... fi
#
# Reads from /dev/tty explicitly, not plain stdin. This matters when
# this script is executed by piping/streaming it in (e.g. deploy.sh's
# remote mode) — in that case stdin is busy carrying the script itself,
# and a plain `read` would consume script bytes instead of waiting for
# the operator to type an answer. /dev/tty is the actual terminal
# regardless of how the script arrived.
confirm() {
  local prompt="${1:-Continue?}"
  local answer
  if [[ -r /dev/tty ]]; then
    read -r -p "${prompt} [y/N] " answer < /dev/tty
  else
    read -r -p "${prompt} [y/N] " answer
  fi
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# Pause and require the operator to explicitly type "yes" — used before
# any step that could lock us out of SSH.
confirm_or_exit() {
  local prompt="$1"
  if ! confirm "$prompt"; then
    die "Aborted by operator."
  fi
}

# --- config loading -------------------------------------------------------
# Loads config/server.env relative to the repo root. Dies with a helpful
# message if it hasn't been created yet.
load_config() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local config_file="${repo_root}/config/server.env"

  if [[ ! -f "$config_file" ]]; then
    die "Missing ${config_file}. Copy config/server.env.example to config/server.env and edit it first."
  fi

  # shellcheck disable=SC1090
  source "$config_file"
}

# --- idempotency helper ---------------------------------------------
# Checks a marker file under /var/lib/vps-hardening/ so a step can skip
# itself if already applied. Not enforced automatically — each script
# decides whether to use it.
STATE_DIR="/var/lib/vps-hardening"

mark_done() {
  mkdir -p "$STATE_DIR"
  touch "${STATE_DIR}/$1.done"
}

is_done() {
  [[ -f "${STATE_DIR}/$1.done" ]]
}
