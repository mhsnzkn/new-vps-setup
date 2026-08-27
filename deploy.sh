#!/usr/bin/env bash
# Run this FROM YOUR LOCAL MACHINE, not on the server.
#
# Unlike an earlier version of this script, this does NOT copy the
# repo to the server and does NOT require rsync or scp on either end.
# It builds a single self-contained bash script locally (this repo's
# shared helpers + your config values + the step you asked for, all
# inlined) and streams it to the server over the existing SSH
# connection, base64-encoded, executed with `bash`. Nothing from this
# repo is left on disk on the server — only what the step itself
# creates (sshd config, ufw rules, packages, etc).
#
# Requires only `ssh` locally and `bash` + `base64` on the remote
# side — both present by default on any stock Debian/Ubuntu box.
#
# Usage:
#   ./deploy.sh [-i identity_file] [-p port] <user@host> [script]
#
#   -i identity_file   Path to a specific SSH private key to connect with.
#                       Omit to use ssh-agent / your default key(s).
#   -p port             SSH port if not 22 (default: 22)
#   user@host           Target server, e.g. deploy@203.0.113.10
#   script              Which step to run (default: 00-main.sh):
#                         00-main.sh, 01-updates.sh, 02-create-user.sh,
#                         03-ssh-hardening.sh, 04-firewall.sh,
#                         05-sysctl-hardening.sh, 06-docker.sh,
#                         nginx.sh, fail2ban.sh
#
# Examples:
#   ./deploy.sh deploy@203.0.113.10
#   ./deploy.sh -i ~/.ssh/vps_key deploy@203.0.113.10 nginx.sh
#   ./deploy.sh -i ~/.ssh/vps_key -p 2222 root@203.0.113.10 fail2ban.sh
#
# Notes:
#   - First run must target root (or a sudo-capable user that already
#     exists) since 00-main.sh itself creates the non-root user.
#   - If your VPS provider already gave you a non-root sudo user with
#     SSH set up, just target that user directly from the start —
#     you don't need root at all. Set NEW_USER in config/server.env
#     to that username; 02-create-user.sh will detect it already
#     exists and offer to use it as-is.
#   - After 03-ssh-hardening.sh runs, root login and password auth are
#     disabled on the server. For any run AFTER that, target the
#     non-root user instead.
#   - Keep this terminal open until each step's own instructions say
#     it's safe to close it — same rule as running locally on the box.

set -euo pipefail

usage() {
  grep '^#' "$0" | sed '1d;s/^# \{0,1\}//'
  exit 1
}

IDENTITY_FILE=""
SSH_PORT="22"

while getopts "i:p:h" opt; do
  case "$opt" in
    i) IDENTITY_FILE="$OPTARG" ;;
    p) SSH_PORT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -ge 1 ]] || usage

TARGET="$1"
REMOTE_SCRIPT="${2:-00-main.sh}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$IDENTITY_FILE" ]]; then
  if [[ ! -f "$IDENTITY_FILE" ]]; then
    echo "[x] Identity file not found: ${IDENTITY_FILE}" >&2
    exit 1
  fi
  PERMS="$(stat -c '%a' "$IDENTITY_FILE" 2>/dev/null || stat -f '%Lp' "$IDENTITY_FILE" 2>/dev/null || echo '')"
  if [[ -n "$PERMS" && "$PERMS" != "600" && "$PERMS" != "400" ]]; then
    echo "[!] ${IDENTITY_FILE} has permissions ${PERMS} — ssh may refuse to use it."
    echo "    Fix with: chmod 600 ${IDENTITY_FILE}"
  fi
  SSH_OPTS=(-i "$IDENTITY_FILE")
else
  SSH_OPTS=()
fi

if [[ ! -f "${REPO_ROOT}/config/server.env" ]]; then
  echo "[x] config/server.env not found locally." >&2
  echo "    Copy config/server.env.example to config/server.env and edit it first." >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/scripts/${REMOTE_SCRIPT}" ]]; then
  echo "[x] scripts/${REMOTE_SCRIPT} does not exist in this repo." >&2
  exit 1
fi

# --- map each script file to the function it defines ------------------
declare -A STEP_FUNCTIONS=(
  ["01-updates.sh"]="step_updates"
  ["02-create-user.sh"]="step_create_user"
  ["03-ssh-hardening.sh"]="step_ssh_hardening"
  ["04-firewall.sh"]="step_firewall"
  ["05-sysctl-hardening.sh"]="step_sysctl_hardening"
  ["06-docker.sh"]="step_docker"
  ["nginx.sh"]="step_nginx"
  ["fail2ban.sh"]="step_fail2ban"
)

MAIN_STEPS=(01-updates.sh 02-create-user.sh 03-ssh-hardening.sh 04-firewall.sh 05-sysctl-hardening.sh 06-docker.sh)

# Prints a script file's content up to (not including) its standalone
# runner block — i.e. just the function definition(s), no execution.
extract_functions() {
  sed '/^# --- standalone runner/,$d' "$1"
}

# --- build the bundle ---------------------------------------------------
build_bundle() {
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo

  echo "# --- embedded: scripts/lib/common.sh ---"
  extract_functions "${REPO_ROOT}/scripts/lib/common.sh"
  echo

  echo "# --- embedded: config/server.env ---"
  cat "${REPO_ROOT}/config/server.env"
  echo

  if [[ "$REMOTE_SCRIPT" == "00-main.sh" ]]; then
    local f
    for f in "${MAIN_STEPS[@]}"; do
      echo "# --- embedded: scripts/${f} ---"
      extract_functions "${REPO_ROOT}/scripts/${f}"
      echo
    done
    echo "# --- embedded: scripts/00-main.sh ---"
    extract_functions "${REPO_ROOT}/scripts/00-main.sh"
    echo
    echo "require_root"
    echo "run_all_steps"
  else
    local fn="${STEP_FUNCTIONS[$REMOTE_SCRIPT]:-}"
    if [[ -z "$fn" ]]; then
      echo "[x] No function mapping for ${REMOTE_SCRIPT}." >&2
      exit 1
    fi
    echo "# --- embedded: scripts/${REMOTE_SCRIPT} ---"
    extract_functions "${REPO_ROOT}/scripts/${REMOTE_SCRIPT}"
    echo
    echo "require_root"
    echo "$fn"
  fi
}

echo "[+] Building self-contained bundle for ${REMOTE_SCRIPT}..."
BUNDLE="$(build_bundle)"
ENCODED="$(printf '%s' "$BUNDLE" | base64 | tr -d '\n')"

echo "[+] Streaming to ${TARGET} (port ${SSH_PORT}) and running — no files uploaded ..."
echo "[+] (interactive session — answer prompts as they appear)"
echo

ssh -t -p "${SSH_PORT}" "${SSH_OPTS[@]}" "${TARGET}" \
  "echo ${ENCODED} | base64 -d | sudo bash"

echo
echo "[+] Remote run of ${REMOTE_SCRIPT} finished."
echo "[+] Don't close this terminal until you've verified the step worked"
echo "    (open a NEW terminal to test SSH login, per docs/verify.md)."
