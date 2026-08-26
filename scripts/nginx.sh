#!/usr/bin/env bash
# Install and do a minimal setup of nginx as a reverse proxy in front
# of Docker containers. Run manually — not part of 00-main.sh, since
# not every server needs a web server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root
load_config

log "Installing nginx..."
apt install -y nginx

log "Ensuring nginx starts on boot..."
systemctl enable --now nginx

if command -v ufw &>/dev/null; then
  log "Allowing 'Nginx Full' (80/tcp + 443/tcp) through UFW..."
  ufw allow 'Nginx Full' || warn "Could not add UFW rule — check ports 80/443 manually."
fi

SITE_AVAILABLE="/etc/nginx/sites-available/reverse-proxy.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/reverse-proxy.conf"

if [[ -f "$SITE_AVAILABLE" ]]; then
  warn "${SITE_AVAILABLE} already exists — leaving it alone."
else
  log "Writing a starter reverse-proxy config to ${SITE_AVAILABLE}..."
  cat > "$SITE_AVAILABLE" <<'EOF'
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
  ln -sf "$SITE_AVAILABLE" "$SITE_ENABLED"
fi

log "Testing nginx config..."
if ! nginx -t; then
  die "nginx -t reported an error. Fix ${SITE_AVAILABLE} before reloading."
fi

systemctl reload nginx

mark_done "nginx"

cat <<EOF

Next steps:
  - Edit ${SITE_AVAILABLE}: set server_name to your real domain and
    proxy_pass to the container/port you're actually running.
  - Add TLS with certbot once DNS is pointed at this server:
      apt install -y certbot python3-certbot-nginx
      certbot --nginx -d example.com

EOF

log "nginx setup complete."
