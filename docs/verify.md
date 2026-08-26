# Verification checklist

Run these after each step (or all at once at the end) to confirm
things actually took effect.

## 1. Updates / unattended-upgrades

```
sudo unattended-upgrades --dry-run --debug
```
Should run without errors and list the configured origins.

```
cat /var/run/reboot-required 2>/dev/null && echo "reboot needed"
```

## 2. User creation

```
id deploy
groups deploy        # should include sudo
```
From a second session:
```
ssh deploy@<server-ip>
sudo whoami           # should print: root
```

## 3. SSH hardening

```
sudo sshd -T | grep -Ei 'permitroot|passwordauth|pubkey|maxauth|logingrace|allowusers'
```
Expected:
```
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
maxauthtries 3
logingracetime 20
allowusers deploy
```
From a *fresh* terminal:
```
ssh deploy@<server-ip>
```
Should log in with your key, no password prompt. Try logging in as
root to confirm it's refused:
```
ssh root@<server-ip>   # should be rejected
```

## 4. Firewall

```
sudo ufw status verbose
```
Expected: default deny incoming, 22/tcp LIMIT, plus whatever ports you
configured. If the server has IPv6, confirm the `(v6)` rules are
present too.

Re-running `04-firewall.sh` reconciles against its own previous run:
if you remove a port from `ALLOWED_TCP_PORTS` and re-run, the old rule
is explicitly deleted rather than left open. It only tracks ports it
allowed itself (recorded in
`/var/lib/vps-hardening/firewall-ports.list`) — rules you added
manually with `ufw allow` outside this script are never touched.

## 5. Sysctl hardening

```
sudo sysctl net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter kernel.randomize_va_space
```
Should reflect the values in `/etc/sysctl.d/99-hardening.conf`.

## 6. Docker

```
docker --version
docker compose version
sudo systemctl status docker --no-pager
```
As the new user (after re-login):
```
docker ps    # should work without sudo
```

## nginx (if installed)

```
sudo nginx -t
sudo systemctl status nginx --no-pager
curl -I http://<server-ip>
```

## General attack-surface sanity check

```
ss -tlnp
```
Anything listening on `0.0.0.0` that isn't SSH, nginx, or something
you deliberately expose should be bound to `127.0.0.1` instead or
disabled. Databases running in Docker should be published to
`127.0.0.1:<port>:<port>`, not `0.0.0.0`, unless nginx or another
container needs to reach them over the network.
