#!/usr/bin/env bash
# Orchestrator: walks through each step, asking for confirmation before
# running it. Answering "n" skips that step and moves on to the next
# one — it does not abort the whole run.
#
# nginx.sh and fail2ban.sh are NOT included here — run them manually
# if/when this box needs them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

# Ordered list of "script:description" pairs.
STEPS=(
  "01-updates.sh:Update packages and enable unattended-upgrades"
  "02-create-user.sh:Create non-root sudo user (${NEW_USER:-unset})"
  "03-ssh-hardening.sh:Harden SSH (disable root login + password auth)"
  "04-firewall.sh:Configure UFW firewall (default-deny, allow 22 + configured ports)"
  "05-sysctl-hardening.sh:Apply sysctl kernel/network hardening"
  "06-docker.sh:Install Docker + Compose"
)

RAN=()
SKIPPED=()

log "Starting VPS hardening pass — you'll be asked before each step."
warn "Keep this session open throughout. Do not close it until told to."
echo

for step in "${STEPS[@]}"; do
  script_name="${step%%:*}"
  description="${step#*:}"

  echo "--------------------------------------------------------------"
  if confirm "Run '${script_name}' — ${description}?"; then
    bash "${SCRIPT_DIR}/${script_name}"
    RAN+=("$script_name")
  else
    warn "Skipping ${script_name}."
    SKIPPED+=("$script_name")
  fi
  echo
done

echo "--------------------------------------------------------------"
log "Run finished."

if [[ ${#RAN[@]} -gt 0 ]]; then
  log "Ran: ${RAN[*]}"
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  warn "Skipped: ${SKIPPED[*]}"
  warn "You can run any skipped step later on its own, e.g.:"
  warn "  sudo bash ${SCRIPT_DIR}/${SKIPPED[0]}"
fi

log "If this server needs a reverse proxy, run: sudo bash ${SCRIPT_DIR}/nginx.sh"
log "If this server needs fail2ban, run: sudo bash ${SCRIPT_DIR}/fail2ban.sh"
log "See docs/verify.md to double check everything took effect."
