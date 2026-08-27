#!/usr/bin/env bash
# Kernel and network sysctl hardening.
#
# Defines step_sysctl_hardening() so this can be sourced/embedded and
# called elsewhere (e.g. deploy.sh's remote streaming mode) without
# touching disk. Running this file directly still works as before.

step_sysctl_hardening() {
  local sysctl_file="/etc/sysctl.d/99-hardening.conf"

  log "Writing sysctl hardening config to ${sysctl_file}..."
  cat > "$sysctl_file" <<'EOF'
# Managed by vps-hardening/scripts/05-sysctl-hardening.sh
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

  log "Applying sysctl settings..."
  sysctl --system

  warn "Note: rp_filter=1 (strict) can drop legit traffic on hosts with"
  warn "asymmetric routing or multiple NICs. If that's this box, change"
  warn "it to 2 (loose mode) in ${sysctl_file} and re-run 'sysctl --system'."

  mark_done "05-sysctl-hardening"
  log "Step 5 complete: sysctl hardening applied."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_sysctl_hardening
fi
