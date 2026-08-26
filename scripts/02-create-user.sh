#!/usr/bin/env bash
# Create a non-root sudo user — or, if NEW_USER already exists on this
# server, offer to just use it as-is (skip password reset / key setup).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

: "${NEW_USER:?NEW_USER must be set in config/server.env}"

USER_HOME="/home/${NEW_USER}"
SSH_DIR="${USER_HOME}/.ssh"

if id "$NEW_USER" &>/dev/null; then
  warn "User '${NEW_USER}' already exists on this server."

  IN_SUDO_GROUP="no"
  id -nG "$NEW_USER" | grep -qw sudo && IN_SUDO_GROUP="yes"
  HAS_KEYS="no"
  [[ -s "${SSH_DIR}/authorized_keys" ]] && HAS_KEYS="yes"

  log "Current state: in sudo group = ${IN_SUDO_GROUP}, has SSH keys = ${HAS_KEYS}"

  if confirm "Use existing user '${NEW_USER}' as-is (skip password reset and key setup)?"; then
    if [[ "$IN_SUDO_GROUP" != "yes" ]]; then
      log "Adding '${NEW_USER}' to the sudo group..."
      usermod -aG sudo "$NEW_USER"
    else
      log "'${NEW_USER}' is already in the sudo group."
    fi

    if [[ "$HAS_KEYS" != "yes" ]]; then
      warn "'${NEW_USER}' has no authorized_keys on file yet."
      warn "SSH hardening (03-ssh-hardening.sh) disables password auth,"
      warn "so make sure this user can log in with a key before running it."
      if confirm "Copy root's authorized_keys to '${NEW_USER}' now?"; then
        mkdir -p "$SSH_DIR"
        touch "${SSH_DIR}/authorized_keys"
        if [[ -f /root/.ssh/authorized_keys ]]; then
          cat /root/.ssh/authorized_keys >> "${SSH_DIR}/authorized_keys"
          sort -u -o "${SSH_DIR}/authorized_keys" "${SSH_DIR}/authorized_keys"
        else
          warn "No /root/.ssh/authorized_keys found to copy."
        fi
        chown -R "${NEW_USER}:${NEW_USER}" "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chmod 600 "${SSH_DIR}/authorized_keys"
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
    # confirmed — not before. If the confirm above fails, the script
    # exits via confirm_or_exit and this line never runs.
    mark_done "02-create-user"
    log "Step 2 complete: using existing user '${NEW_USER}'."
    exit 0
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
mkdir -p "$SSH_DIR"
touch "${SSH_DIR}/authorized_keys"

if [[ -f /root/.ssh/authorized_keys ]]; then
  log "Copying root's authorized_keys to ${NEW_USER}..."
  cat /root/.ssh/authorized_keys >> "${SSH_DIR}/authorized_keys"
fi

if [[ -n "${NEW_USER_PUBKEY_FILE:-}" && -f "${NEW_USER_PUBKEY_FILE}" ]]; then
  log "Adding key from ${NEW_USER_PUBKEY_FILE}..."
  cat "${NEW_USER_PUBKEY_FILE}" >> "${SSH_DIR}/authorized_keys"
fi

sort -u -o "${SSH_DIR}/authorized_keys" "${SSH_DIR}/authorized_keys"

chown -R "${NEW_USER}:${NEW_USER}" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "${SSH_DIR}/authorized_keys"

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
# confirmed — not before. If the confirm above fails, the script
# exits via confirm_or_exit and this line never runs.
mark_done "02-create-user"

log "Step 2 complete: user '${NEW_USER}' created and verified."
