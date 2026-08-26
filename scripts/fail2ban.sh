#!/usr/bin/env bash
# Install and configure fail2ban for sshd. Standalone — not called from
# 00-main.sh, run it manually if/when you want it on a given server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

log "Installing fail2ban..."
apt install -y fail2ban

# Derive the SSH port from the live sshd config rather than hardcoding
# it, so this stays correct even if the port was changed outside this
# repo (this repo itself never changes it from 22 — see README).
SSH_LIVE_PORT="$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
SSH_LIVE_PORT="${SSH_LIVE_PORT:-22}"
log "Detected live sshd port: ${SSH_LIVE_PORT}"

JAIL_LOCAL="/etc/fail2ban/jail.local"

if [[ -f "$JAIL_LOCAL" ]]; then
  warn "${JAIL_LOCAL} already exists — leaving it alone. Delete it and re-run to reset."
else
  log "Writing ${JAIL_LOCAL}..."
  cat > "$JAIL_LOCAL" <<EOF
# Managed by vps-hardening/scripts/fail2ban.sh
[DEFAULT]
# How long a ban lasts.
bantime  = 1h
# Window in which maxretry failures trigger a ban.
findtime = 10m
maxretry = 5
# Ban repeat offenders for longer each time.
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w

# sshd's own log-based backend is unnecessary/unreliable on systems
# that only log to the systemd journal — use systemd backend instead.
backend = systemd

[sshd]
enabled = true
port    = ${SSH_LIVE_PORT}
EOF
fi

log "Enabling and starting fail2ban..."
systemctl enable --now fail2ban

log "Restarting to pick up jail.local..."
systemctl restart fail2ban

sleep 1

# --- verify before declaring success -------------------------------------
if ! systemctl is-active --quiet fail2ban; then
  die "fail2ban service is not active after restart. Check 'systemctl status fail2ban' and 'journalctl -u fail2ban' before relying on it."
fi

if ! fail2ban-client status sshd &>/dev/null; then
  die "fail2ban-client cannot reach the sshd jail. The service is running but the jail may have failed to load — check 'journalctl -u fail2ban'."
fi

log "fail2ban status:"
fail2ban-client status
fail2ban-client status sshd

# Only mark this step done once the service and jail are confirmed
# healthy above — not before.
mark_done "fail2ban"

cat <<EOF

Useful commands:
  fail2ban-client status sshd          # show current bans for sshd jail
  fail2ban-client set sshd unbanip IP  # manually unban an IP
  fail2ban-client banned                # list all banned IPs across jails

EOF

log "fail2ban setup complete."
