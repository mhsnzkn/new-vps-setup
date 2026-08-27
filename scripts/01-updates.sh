#!/usr/bin/env bash
# Update the system and enable automatic security updates.
#
# Defines step_updates() so this can be sourced/embedded and called
# elsewhere (e.g. deploy.sh's remote streaming mode) without touching
# disk. Running this file directly still works exactly as before.

step_updates() {
  log "Updating package lists and upgrading installed packages..."
  apt update
  apt full-upgrade -y
  apt autoremove --purge -y

  log "Installing unattended-upgrades, apt-listchanges, needrestart..."
  apt install -y unattended-upgrades apt-listchanges needrestart

  log "Enabling unattended-upgrades..."
  dpkg-reconfigure -f noninteractive -plow unattended-upgrades

  local uu_conf="/etc/apt/apt.conf.d/50unattended-upgrades"
  if [[ -f "$uu_conf" ]]; then
    log "Ensuring automatic reboot + notification settings are enabled in ${uu_conf}..."
    sed -i \
      -e 's|^//\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' \
      -e 's|^//\s*Unattended-Upgrade::Automatic-Reboot-Time.*|Unattended-Upgrade::Automatic-Reboot-Time "04:00";|' \
      -e 's|^//\s*Unattended-Upgrade::Remove-Unused-Dependencies.*|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' \
      "$uu_conf"

    # Add lines if they weren't present at all (fresh installs vary)
    grep -q "Automatic-Reboot " "$uu_conf" || echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$uu_conf"
    grep -q "Automatic-Reboot-Time " "$uu_conf" || echo 'Unattended-Upgrade::Automatic-Reboot-Time "04:00";' >> "$uu_conf"
  fi

  if [[ -n "${TIMEZONE:-}" ]]; then
    log "Setting timezone to ${TIMEZONE}..."
    timedatectl set-timezone "$TIMEZONE" || warn "Could not set timezone to ${TIMEZONE}"
  fi

  log "Dry-run check of unattended-upgrades:"
  unattended-upgrades --dry-run --debug || warn "Dry-run reported an issue — review output above."

  if [[ -f /var/run/reboot-required ]]; then
    warn "A reboot is required (kernel or libc was updated)."
    warn "Reboot manually with 'sudo reboot' when convenient, ideally before continuing."
  fi

  mark_done "01-updates"
  log "Step 1 complete: system updated, unattended-upgrades enabled."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_updates
fi
