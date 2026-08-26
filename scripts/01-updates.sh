#!/usr/bin/env bash
# Update the system and enable automatic security updates.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

log "Updating package lists and upgrading installed packages..."
apt update
apt full-upgrade -y
apt autoremove --purge -y

log "Installing unattended-upgrades, apt-listchanges, needrestart..."
apt install -y unattended-upgrades apt-listchanges needrestart

log "Enabling unattended-upgrades..."
dpkg-reconfigure -f noninteractive -plow unattended-upgrades

UU_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
if [[ -f "$UU_CONF" ]]; then
  log "Ensuring automatic reboot + notification settings are enabled in ${UU_CONF}..."
  sed -i \
    -e 's|^//\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' \
    -e 's|^//\s*Unattended-Upgrade::Automatic-Reboot-Time.*|Unattended-Upgrade::Automatic-Reboot-Time "04:00";|' \
    -e 's|^//\s*Unattended-Upgrade::Remove-Unused-Dependencies.*|Unattended-Upgrade::Remove-Unused-Dependencies "true";|' \
    "$UU_CONF"

  # Add lines if they weren't present at all (fresh installs vary)
  grep -q "Automatic-Reboot " "$UU_CONF" || echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$UU_CONF"
  grep -q "Automatic-Reboot-Time " "$UU_CONF" || echo 'Unattended-Upgrade::Automatic-Reboot-Time "04:00";' >> "$UU_CONF"
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
