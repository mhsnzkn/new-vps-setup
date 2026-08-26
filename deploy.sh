#!/usr/bin/env bash
# Run this FROM YOUR LOCAL MACHINE, not on the server.
#
# It copies this repo to the target server and runs the chosen script
# there over an interactive SSH session (so the pause/confirm prompts
# in the scripts still work).
#
# Usage:
#   ./deploy.sh <user@host> [script] [ssh-port]
#
#   user@host   Target server, e.g. root@203.0.113.10
#   script      Script under scripts/ to run (default: 00-main.sh)
#   ssh-port    SSH port if not 22 (default: 22)
#
# Examples:
#   ./deploy.sh root@203.0.113.10                    # full pass (00-main.sh)
#   ./deploy.sh root@203.0.113.10 nginx.sh
#   ./deploy.sh deploy@203.0.113.10 fail2ban.sh 22
#
# Notes:
#   - First run must target root (or a sudo-capable user that already
#     exists) since 00-main.sh itself creates the non-root user.
#   - After 03-ssh-hardening.sh runs, root login and password auth are
#     disabled on the server. For any run AFTER that, target the new
#     user instead, e.g. ./deploy.sh deploy@203.0.113.10 nginx.sh
#   - Keep this terminal open until each step's own instructions say
#     it's safe to close it — same rule as running locally on the box.

set -euo pipefail

usage() {
  grep '^#' "$0" | sed '1d;s/^# \{0,1\}//'
  exit 1
}

[[ $# -ge 1 ]] || usage

TARGET="$1"
REMOTE_SCRIPT="${2:-00-main.sh}"
SSH_PORT="${3:-22}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="vps-hardening"

if [[ ! -f "${REPO_ROOT}/config/server.env" ]]; then
  echo "[x] config/server.env not found locally." >&2
  echo "    Copy config/server.env.example to config/server.env and edit it first." >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/scripts/${REMOTE_SCRIPT}" ]]; then
  echo "[x] scripts/${REMOTE_SCRIPT} does not exist in this repo." >&2
  exit 1
fi

echo "[+] Copying repo to ${TARGET}:~/${REMOTE_DIR} (port ${SSH_PORT}) ..."
if command -v rsync &>/dev/null; then
  rsync -az --delete \
    -e "ssh -p ${SSH_PORT}" \
    --exclude '.git' \
    "${REPO_ROOT}/" "${TARGET}:${REMOTE_DIR}/"
else
  echo "[!] rsync not found locally, falling back to scp (slower, no --delete)."
  ssh -p "${SSH_PORT}" "${TARGET}" "mkdir -p ${REMOTE_DIR}"
  scp -P "${SSH_PORT}" -r "${REPO_ROOT}/." "${TARGET}:${REMOTE_DIR}/"
fi

echo "[+] Running scripts/${REMOTE_SCRIPT} on ${TARGET} ..."
echo "[+] (interactive session — answer prompts as they appear)"
echo

ssh -t -p "${SSH_PORT}" "${TARGET}" \
  "cd ${REMOTE_DIR} && sudo bash scripts/${REMOTE_SCRIPT}"

echo
echo "[+] Remote run of ${REMOTE_SCRIPT} finished."
echo "[+] Don't close this terminal until you've verified the step worked"
echo "    (open a NEW terminal to test SSH login, per docs/verify.md)."
