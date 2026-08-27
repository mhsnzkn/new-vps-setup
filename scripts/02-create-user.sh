#!/usr/bin/env bash
# Create a non-root sudo user — or, if NEW_USER already exists on this
# server, offer to just use it as-is (skip password reset / key setup).
#
# Defines step_create_user() so this can be sourced/embedded and called
# elsewhere (e.g. deploy.sh's remote streaming mode) without touching
# disk. Running this file directly still works exactly as before.

step_create_user() {
  : "${NEW_USER:?NEW_USER must be set in config/server.env}"

  local user_home="/home/${NEW_USER}"
  local ssh_dir="${user_home}/.ssh"

  if id "$NEW_USER" &>/dev/null; then
    warn "User '${NEW_USER}' already exists on this server."

    local in_sudo_group="no"
    id -nG "$NEW_USER" | grep -qw sudo && in_sudo_group="yes"
    local has_keys="no"
    [[ -s "${ssh_dir}/authorized_keys" ]] && has_keys="yes"

    log "Current state: in sudo group = ${in_sudo_group}, has SSH keys = ${has_keys}"

    if confirm "Use existing user '${NEW_USER}' as-is (skip password reset and key setup)?"; then
      if [[ "$in_sudo_group" != "yes" ]]; then
        log "Adding '${NEW_USER}' to the sudo group..."
        usermod -aG sudo "$NEW_USER"
      else
        log "'${NEW_USER}' is already in the sudo group."
      fi

      if [[ "$has_keys" != "yes" ]]; then
        warn "'${NEW_USER}' has no authorized_keys on file yet."
        warn "SSH hardening (03-ssh-hardening.sh) disables password auth,"
        warn "so make sure this user can log in with a key before running it."
        if confirm "Copy root's authorized_keys to '${NEW_USER}' now?"; then
          mkdir -p "$ssh_dir"
          touch "${ssh_dir}/authorized_keys"
          if [[ -f /root/.ssh/authorized_keys ]]; then
            cat /root/.ssh/authorized_keys >> "${ssh_dir}/authorized_keys"
            sort -u -o "${ssh_dir}/authorized_keys" "${ssh_dir}/authorized_keys"
          else
            warn "No /root/.ssh/authorized_keys found to copy."
          fi
          chown -R "${NEW_USER}:${NEW_USER}" "$ssh_dir"
          chmod 700 "$ssh_dir"
          chmod 600 "${ssh_dir}/authorized_keys"
        fi
      fi

      cat <<EOF

$(echo -e "${COLOR_YELLOW}--- STOP AND VERIFY BEFORE CONTINUING ---${COLOR_RESET}")

Open a NEW, second SSH session (keep this one open) and confirm:

    ssh ${NEW_USER}@<this-server-ip>
    sudo whoami        # should print: root

Do NOT proceed to SSH hardening (03-ssh-hardening.sh) until that
works.

EOF

      confirm_or_exit "Have you verified '${NEW_USER}' can log in and sudo in a second session?"

      # Only mark this step done once verification has actually been
      # confirmed — not before. If the confirm above fails,
      # confirm_or_exit calls die() which exits the whole process.
      mark_done "02-create-user"
      log "Step 2 complete: using existing user '${NEW_USER}'."
      return 0
    fi

    log "Proceeding with full setup for '${NEW_USER}' (password reset + key setup) below."
  else
    log "Creating user '${NEW_USER}'..."
    adduser --disabled-password --gecos "" "$NEW_USER"
  fi

  log "Adding '${NEW_USER}' to the sudo group..."
  usermod -aG sudo "$NEW_USER"

  # --- password ---------------------------------------------------------
  if [[ -n "${NEW_USER_PASSWORD:-}" ]]; then
    log "Setting password for '${NEW_USER}' from config..."
    echo "${NEW_USER}:${NEW_USER_PASSWORD}" | chpasswd
  else
    log "No password set in config — you'll be prompted now."
    passwd "$NEW_USER"
  fi

  # --- SSH keys ---------------------------------------------------------
  mkdir -p "$ssh_dir"
  touch "${ssh_dir}/authorized_keys"

  if [[ -f /root/.ssh/authorized_keys ]]; then
    log "Copying root's authorized_keys to ${NEW_USER}..."
    cat /root/.ssh/authorized_keys >> "${ssh_dir}/authorized_keys"
  fi

  if [[ -n "${NEW_USER_PUBKEY_FILE:-}" && -f "${NEW_USER_PUBKEY_FILE}" ]]; then
    log "Adding key from ${NEW_USER_PUBKEY_FILE}..."
    cat "${NEW_USER_PUBKEY_FILE}" >> "${ssh_dir}/authorized_keys"
  fi

  sort -u -o "${ssh_dir}/authorized_keys" "${ssh_dir}/authorized_keys"

  chown -R "${NEW_USER}:${NEW_USER}" "$ssh_dir"
  chmod 700 "$ssh_dir"
  chmod 600 "${ssh_dir}/authorized_keys"

  cat <<EOF

$(echo -e "${COLOR_YELLOW}--- STOP AND VERIFY BEFORE CONTINUING ---${COLOR_RESET}")

Open a NEW, second SSH session (keep this one open) and confirm:

    ssh ${NEW_USER}@<this-server-ip>
    sudo whoami        # should print: root

Do NOT proceed to SSH hardening (03-ssh-hardening.sh) until that
works. If it doesn't work, fix it now while this root session is
still alive.

EOF

  confirm_or_exit "Have you verified '${NEW_USER}' can log in and sudo in a second session?"

  # Only mark this step done once verification has actually been
  # confirmed — not before.
  mark_done "02-create-user"

  log "Step 2 complete: user '${NEW_USER}' created and verified."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_create_user
fi
