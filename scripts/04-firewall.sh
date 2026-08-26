#!/usr/bin/env bash
# Default-deny firewall via UFW. Port 22 is always allowed.
# Extra ports come from ALLOWED_TCP_PORTS in config/server.env.
#
# Re-running this script reconciles rules against the PREVIOUS run of
# this script: ports that were allowed before but have since been
# removed from ALLOWED_TCP_PORTS get explicitly revoked, not just
# left open. This only touches ports this script itself has allowed —
# rules you added manually with `ufw allow` outside this script are
# left alone.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

PORTS_STATE_FILE="${STATE_DIR}/firewall-ports.list"

log "Installing UFW..."
apt install -y ufw

log "Setting default policy: deny incoming, allow outgoing..."
ufw default deny incoming
ufw default allow outgoing

log "Allowing SSH (port 22) — required before enabling the firewall..."
ufw allow 22/tcp
ufw limit 22/tcp

# --- read previous ports managed by this script --------------------------
PREV_PORTS=()
if [[ -f "$PORTS_STATE_FILE" ]]; then
  # shellcheck disable=SC2207
  PREV_PORTS=($(cat "$PORTS_STATE_FILE"))
fi

CURRENT_PORTS=()
if [[ -n "${ALLOWED_TCP_PORTS:-}" ]]; then
  # shellcheck disable=SC2207
  CURRENT_PORTS=(${ALLOWED_TCP_PORTS})
fi

# --- revoke ports that were allowed before but are no longer configured --
for old_port in "${PREV_PORTS[@]:-}"; do
  [[ -z "$old_port" ]] && continue
  still_wanted="no"
  for new_port in "${CURRENT_PORTS[@]:-}"; do
    if [[ "$old_port" == "$new_port" ]]; then
      still_wanted="yes"
      break
    fi
  done
  if [[ "$still_wanted" == "no" ]]; then
    warn "Port ${old_port} was allowed by a previous run but is no longer in ALLOWED_TCP_PORTS — removing rule."
    ufw delete allow "${old_port}/tcp" 2>/dev/null || warn "Could not delete rule for ${old_port}/tcp (may already be gone)."
  fi
done

# --- allow current ports -------------------------------------------------
if [[ ${#CURRENT_PORTS[@]} -gt 0 ]]; then
  for port in "${CURRENT_PORTS[@]}"; do
    log "Allowing TCP port ${port}..."
    ufw allow "${port}/tcp"
  done
else
  warn "No ALLOWED_TCP_PORTS set — only SSH will be open."
fi

confirm_or_exit "About to enable UFW. Port 22 is allowed above — confirm this looks right before enabling."

ufw --force enable

# Persist current port list so the next run can reconcile against it.
mkdir -p "$STATE_DIR"
printf '%s\n' "${CURRENT_PORTS[@]:-}" > "$PORTS_STATE_FILE"

mark_done "04-firewall"

log "Step 4 complete. Current rules:"
ufw status verbose
