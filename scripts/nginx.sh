#!/usr/bin/env bash
# Install and do a minimal setup of nginx as a reverse proxy in front
# of Docker containers. Not part of 00-main.sh, since not every server
# needs a web server.
#
# Defines step_nginx() so this can be sourced/embedded and called
# elsewhere (e.g. deploy.sh's remote streaming mode) without touching
# disk. Running this file directly still works exactly as before.

step_nginx() {
  log "Installing nginx..."
  apt install -y nginx

  log "Ensuring nginx starts on boot..."
  systemctl enable --now nginx

  if command -v ufw &>/dev/null; then
    log "Allowing 'Nginx Full' (80/tcp + 443/tcp) through UFW..."
    ufw allow 'Nginx Full' || warn "Could not add UFW rule — check ports 80/443 manually."
  fi

  local site_available="/etc/nginx/sites-available/reverse-proxy.conf"
  local site_enabled="/etc/nginx/sites-enabled/reverse-proxy.conf"

  if [[ -f "$site_available" ]]; then
    warn "${site_available} already exists — leaving it alone."
  else
    log "Writing a starter reverse-proxy config to ${site_available}..."
    cat > "$site_available" <<'EOF'
# Starter reverse-proxy config.
# Point this at a container published on localhost, e.g. via
# `-p 127.0.0.1:3000:3000` in your docker run / compose file.
#
# Duplicate this block per app/domain and edit server_name + proxy_pass.

server {
    listen 80;
    listen [::]:80;
    server_name example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    ln -sf "$site_available" "$site_enabled"
  fi

  log "Testing nginx config..."
  if ! nginx -t; then
    die "nginx -t reported an error. Fix ${site_available} before reloading."
  fi

  systemctl reload nginx

  mark_done "nginx"

  cat <<EOF

Next steps:
  - Edit ${site_available}: set server_name to your real domain and
    proxy_pass to the container/port you're actually running.
  - Add TLS with certbot once DNS is pointed at this server:
      apt install -y certbot python3-certbot-nginx
      certbot --nginx -d example.com

EOF

  log "nginx setup complete."
}

# --- standalone runner (only runs when this file is executed directly) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  require_root
  load_config
  step_nginx
fi
