#!/usr/bin/env bash
# Default-deny firewall via UFW. Port 22 is always allowed.
# Extra ports come from ALLOWED_TCP_PORTS in config/server.env.
#
# Re-running this reconciles against the PREVIOUS run: ports that were
# allowed before but have since been removed from ALLOWED_TCP_PORTS get
# explicitly revoked. Only touches ports this script itself allowed.
#
# Defines step_firewall() so this can be sourced/embedded and called
# elsewhere (e.g. deploy.sh's remote streaming mode) without touching
# disk. Running this file directly still works exactly as before.

step_firewall() {
  local ports_state_file="${STATE_DIR}/firewall-ports.list"

  log "Installing UFW..."
  apt install -y ufw

  log "Setting default policy: deny incoming, allow outgoing..."
  ufw default deny incoming
  ufw default allow outgoing

  log "Allowing SSH (port 22) — required before enabling the firewall..."
  ufw allow 22/tcp
  ufw limit 22/tcp

  # --- read previous ports managed by this script ---------------------
  local prev_ports=()
  if [[ -f "$ports_state_file" ]]; then
    # shellcheck disable=SC2207
    prev_ports=($(cat "$ports_state_file"))
  fi

  local current_ports=()
  if [[ -n "${ALLOWED_TCP_PORTS:-}" ]]; then
    # shellcheck disable=SC2207
    current_ports=(${ALLOWED_TCP_PORTS})
  fi

  # --- revoke ports no longer configured --------------------------------
  local old_port new_port still_wanted
  for old_port in "${prev_ports[@]:-}"; do
    [[ -z "$old_port" ]] && continue
    still_wanted="no"
    for new_port in "${current_ports[@]:-}"; do
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

  # --- allow current ports -----------------------------------------------
  if [[ ${#current_ports[@]} -gt 0 ]]; then
    for port in "${current_ports[@]}"; do
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
  printf '%s\n' "${current_ports[@]:-}" > "$ports_state_file"

  mark_done "04-firewall"

  log "Step 4 complete. Current rules:"
  ufw status verbose
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_firewall
fi
