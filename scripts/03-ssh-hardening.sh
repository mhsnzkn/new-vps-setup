#!/usr/bin/env bash
# Harden sshd: disable root login and password auth, key-only.
# Port is intentionally left at 22 (see config/server.env.example).
#
# Defines step_ssh_hardening() so this can be sourced/embedded and
# called elsewhere (e.g. deploy.sh's remote streaming mode) without
# touching disk. Running this file directly still works as before.

step_ssh_hardening() {
  : "${NEW_USER:?NEW_USER must be set in config/server.env}"

  if ! is_done "02-create-user"; then
    warn "02-create-user does not appear to have completed (no state marker found)."
    confirm_or_exit "Have you already created '${NEW_USER}' and verified you can log in as them with sudo, in a SEPARATE session right now?"
  fi

  # --- concrete pre-flight checks -----------------------------------
  # sshd -t only proves the config file parses. It says nothing about
  # whether the user we're about to restrict access to can actually
  # log in. Check the things we can actually verify before touching sshd.

  if ! id "$NEW_USER" &>/dev/null; then
    die "User '${NEW_USER}' does not exist on this system. Run 02-create-user.sh first."
  fi

  local authorized_keys="/home/${NEW_USER}/.ssh/authorized_keys"
  if [[ ! -s "$authorized_keys" ]]; then
    warn "No authorized_keys found (or it's empty) at ${authorized_keys}."
    warn "This step disables password authentication. If '${NEW_USER}' has no"
    warn "working key, you will lock yourself out of SSH entirely."
    confirm_or_exit "Proceed anyway? (only if you've set up key access another way)"
  fi

  if ! id -nG "$NEW_USER" | grep -qw sudo; then
    warn "'${NEW_USER}' is not in the sudo group. They'll be able to log in but not sudo."
    confirm_or_exit "Proceed anyway?"
  fi

  local dropin_dir="/etc/ssh/sshd_config.d"
  local dropin_file="${dropin_dir}/00-hardening.conf"

  mkdir -p "$dropin_dir"

  log "Writing SSH hardening drop-in to ${dropin_file}..."
  cat > "$dropin_file" <<EOF
# Managed by vps-hardening/scripts/03-ssh-hardening.sh
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
AuthenticationMethods publickey
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 20
AllowUsers ${NEW_USER}
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GSSAPIAuthentication no
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
EOF

  log "Validating sshd configuration syntax before reloading..."
  if ! sshd -t; then
    die "sshd -t reported a config error. NOT reloading. Fix ${dropin_file} and re-run."
  fi
  log "Syntax OK — note this only checks the file parses, not that login will work."

  warn "About to reload sshd with root login and password auth disabled."
  warn "Keep your current root session open. Confirm '${NEW_USER}' can already log in via key."
  confirm_or_exit "Reload sshd now?"

  systemctl reload ssh

  log "sshd reloaded. Current effective settings:"
  sshd -T | grep -Ei 'permitroot|passwordauth|pubkey|maxauth|logingrace|allowusers'

  cat <<EOF

$(echo -e "${COLOR_YELLOW}--- STOP AND VERIFY IN A FRESH SESSION ---${COLOR_RESET}")

Open a BRAND NEW terminal (not one already logged in) and confirm:

    ssh ${NEW_USER}@<this-server-ip>

This should log you in with your key and NOT ask for a password.
Keep this current session open until that's confirmed — this is your
rollback path if something's wrong (edit ${dropin_file} and
'systemctl reload ssh' again, or delete it and reload).

EOF

  confirm_or_exit "Have you verified '${NEW_USER}' can log in via key in a fresh session?"

  # Only mark this step done once verification has actually been
  # confirmed — not before.
  mark_done "03-ssh-hardening"

  log "Step 3 complete: SSH hardened and verified."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_ssh_hardening
fi
