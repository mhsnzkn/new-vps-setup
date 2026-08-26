# Runbook: provisioning a new server

## Before you start

- Fresh Ubuntu 24.04 or Debian 12/13 VPS with a public IP and root access.
- If your provider has a network-level firewall (Hetzner Cloud Firewall,
  AWS security groups, etc.), configure it first: allow inbound 22, 80,
  443 only. This is a free layer that stands even if you misconfigure
  the host firewall.
- 30 minutes, and don't rush the SSH steps.

## Steps

1. **Get the repo onto the server.**
   ```
   scp -r vps-hardening root@<server-ip>:/root/
   ssh root@<server-ip>
   ```

2. **Configure.**
   ```
   cd vps-hardening
   cp config/server.env.example config/server.env
   nano config/server.env
   ```
   At minimum set `NEW_USER`. Leave `NEW_USER_PASSWORD` blank to be
   prompted interactively rather than storing it in the file.

3. **Run the main script.**
   ```
   sudo bash scripts/00-main.sh
   ```
   It will ask, before each step, something like:
   ```
   Run '01-updates.sh' — Update packages and enable unattended-upgrades? [y/N]
   ```
   Answer `y` to run that step, or `n`/Enter to skip it and move on to
   the next one. Skipping a step does not stop the run — you get asked
   about every step in order, and a summary of what ran vs. was
   skipped is printed at the end. You can always run a skipped step
   later on its own, e.g. `sudo bash scripts/04-firewall.sh`.

4. **When it pauses after user creation** — open a *second* terminal,
   don't close the first:
   ```
   ssh deploy@<server-ip>
   sudo whoami   # should print: root
   ```
   Only answer "yes" to continue in the main script once this works.

   **Already have this user on the box?** Set `NEW_USER` in
   `config/server.env` to that existing username. When
   `02-create-user.sh` runs, it detects the user already exists and
   asks whether to use it as-is — if you say yes, it skips the
   password reset and key setup, only adding them to the `sudo` group
   if needed and offering to copy root's key over if they don't have
   one yet. It still marks the step done and still makes you verify
   login in a second session before moving on to SSH hardening.

5. **Before SSH hardening reloads sshd**, make sure your key is already
   working for the new user (previous step covers this). The script
   validates config with `sshd -t` before reloading, but validation
   can't catch "your key isn't actually installed."

6. **After SSH hardening finishes**, open a *brand new* terminal (not
   one already authenticated) and confirm:
   ```
   ssh deploy@<server-ip>
   ```
   You should get in with your key, no password prompt. Keep the
   original root session open until this is confirmed.

7. **Firewall step** allows port 22 before enabling UFW — if you have
   other ports to open beyond 80/443, add them to `ALLOWED_TCP_PORTS`
   in `config/server.env` before running, or run `ufw allow <port>/tcp`
   afterwards.

8. **Docker** installs and adds `NEW_USER` to the `docker` group. Log
   out/in as that user afterwards for the group membership to apply.

9. **If this server runs a reverse proxy**, run nginx separately:
   ```
   sudo bash scripts/nginx.sh
   ```
   Edit `/etc/nginx/sites-available/reverse-proxy.conf` afterwards to
   point at your actual domain and container port.

10. **Verify everything** — see `docs/verify.md`.

## Re-running a single step

Every script under `scripts/` sources its own config and can be run
standalone, e.g. to re-apply firewall rules on an existing box:
```
sudo bash scripts/04-firewall.sh
```

## Known gotchas (from the reference article)

- On Ubuntu 24.04, `ssh.socket` owns the listening port — a `Port`
  line in `sshd_config` is silently ignored. This repo doesn't change
  the SSH port for exactly this reason.
- `sshd_config.d` files are read alphabetically; the first match for a
  given option wins. Cloud-init images sometimes ship a
  `50-cloud-init.conf` that sets things first. This repo names its
  drop-in `00-hardening.conf` so it sorts first and wins.
- The classic lockout mistakes: enabling UFW before allowing SSH, and
  disabling password auth before confirming key login works. Both
  scripts here guard against this with explicit confirmations — don't
  bypass them.
