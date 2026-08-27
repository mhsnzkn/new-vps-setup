#!/usr/bin/env bash
# Install Docker Engine + Compose plugin from Docker's official repo,
# and add NEW_USER to the docker group.
#
# Defines step_docker() so this can be sourced/embedded and called
# elsewhere (e.g. deploy.sh's remote streaming mode) without touching
# disk. Running this file directly still works exactly as before.

step_docker() {
  if [[ "${INSTALL_DOCKER:-true}" != "true" ]]; then
    log "INSTALL_DOCKER is not 'true' in config — skipping."
    return 0
  fi

  if command -v docker &>/dev/null; then
    warn "Docker already installed ($(docker --version)) — skipping install."
  else
    log "Installing prerequisites..."
    apt install -y ca-certificates curl gnupg

    . /etc/os-release  # provides $ID, $VERSION_CODENAME
    local distro_id="$ID"

    # Docker only publishes repos for these distros. Ubuntu/Debian
    # derivatives (Pop!_OS, Linux Mint, etc.) report their own $ID here
    # and this URL will 404 for them even though apt won't fail loudly
    # until later. Check up front instead of assuming.
    local supported_distros=("ubuntu" "debian")
    local is_supported="no"
    local d
    for d in "${supported_distros[@]}"; do
      [[ "$distro_id" == "$d" ]] && is_supported="yes"
    done

    if [[ "$is_supported" != "yes" ]]; then
      warn "Detected distro ID '${distro_id}' — Docker's official repo only supports: ${supported_distros[*]}."
      warn "This is likely a derivative distro. Docker's repo for '${distro_id}' probably does not exist."
      confirm_or_exit "Attempt to add the Docker repo using '${distro_id}' anyway (may fail)?"
    fi

    log "Adding Docker's official GPG key and repo for ${distro_id}..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${distro_id}/gpg" \
      -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    local arch
    arch="$(dpkg --print-architecture)"
    echo \
      "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro_id} ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

    apt update
    log "Installing docker-ce, docker-ce-cli, containerd.io, docker compose plugin..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  if [[ -n "${NEW_USER:-}" ]] && id "$NEW_USER" &>/dev/null; then
    log "Adding '${NEW_USER}' to the docker group (lets them run docker without sudo)..."
    usermod -aG docker "$NEW_USER"
    warn "'${NEW_USER}' needs to log out and back in for the group change to apply."
  fi

  systemctl enable --now docker

  mark_done "06-docker"

  log "Step 6 complete. Docker version:"
  docker --version
  docker compose version
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_docker
fi
