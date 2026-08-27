#!/usr/bin/env bash
# Orchestrator: walks through each step, asking for confirmation before
# running it. Answering "n" skips that step and moves on to the next
# one — it does not abort the whole run.
#
# nginx.sh and fail2ban.sh are NOT included here — run them manually
# if/when this box needs them.
#
# Defines run_all_steps() (calling step functions directly, not
# spawning `bash <file>`) so this can be embedded and streamed
# elsewhere (e.g. deploy.sh's remote mode) without any files on disk.
# Running this file directly still works exactly as before.

STEPS=(
  "step_updates:01-updates.sh:Update packages and enable unattended-upgrades"
  "step_create_user:02-create-user.sh:Create non-root sudo user (${NEW_USER:-unset})"
  "step_ssh_hardening:03-ssh-hardening.sh:Harden SSH (disable root login + password auth)"
  "step_firewall:04-firewall.sh:Configure UFW firewall (default-deny, allow 22 + configured ports)"
  "step_sysctl_hardening:05-sysctl-hardening.sh:Apply sysctl kernel/network hardening"
  "step_docker:06-docker.sh:Install Docker + Compose"
)

run_all_steps() {
  local ran=()
  local skipped=()

  log "Starting VPS hardening pass — you'll be asked before each step."
  warn "Keep this session open throughout. Do not close it until told to."
  echo

  local step fn_name file_name description
  for step in "${STEPS[@]}"; do
    fn_name="$(echo "$step" | cut -d: -f1)"
    file_name="$(echo "$step" | cut -d: -f2)"
    description="$(echo "$step" | cut -d: -f3-)"

    echo "--------------------------------------------------------------"
    if confirm "Run '${file_name}' — ${description}?"; then
      "$fn_name"
      ran+=("$file_name")
    else
      warn "Skipping ${file_name}."
      skipped+=("$file_name")
    fi
    echo
  done

  echo "--------------------------------------------------------------"
  log "Run finished."

  if [[ ${#ran[@]} -gt 0 ]]; then
    log "Ran: ${ran[*]}"
  fi
  if [[ ${#skipped[@]} -gt 0 ]]; then
    warn "Skipped: ${skipped[*]}"
    warn "You can run any skipped step later on its own, e.g.:"
    warn "  sudo bash scripts/${skipped[0]}"
  fi

  log "If this server needs a reverse proxy, run: sudo bash scripts/nginx.sh"
  log "If this server needs fail2ban, run: sudo bash scripts/fail2ban.sh"
  log "See docs/verify.md to double check everything took effect."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config

  # Source the individual step files so their step_*() functions are
  # defined. Sourcing (not executing) them is a no-op beyond that,
  # thanks to each file's own standalone-runner guard.
  source "$SCRIPT_DIR/01-updates.sh"
  source "$SCRIPT_DIR/02-create-user.sh"
  source "$SCRIPT_DIR/03-ssh-hardening.sh"
  source "$SCRIPT_DIR/04-firewall.sh"
  source "$SCRIPT_DIR/05-sysctl-hardening.sh"
  source "$SCRIPT_DIR/06-docker.sh"

  run_all_steps
fi
