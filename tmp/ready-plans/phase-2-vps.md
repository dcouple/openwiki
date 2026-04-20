# autoblog Phase 2 — VPS Deployment

## Overview

Moves the validated Phase 1 system to a public-facing VPS. At the end of this phase:

- The same Docker image, same `compose.yml`, and same agent templates run on a VPS — not a rebuild, just a different `.env`.
- `https://<your-domain>` serves the production Astro site with automatic Let's Encrypt TLS via Caddy.
- `ssh -p 2222 autoblog@<your-domain>` drops you into the agent's tmux session from anywhere with an internet connection.
- `autoblog --tunnel` on your laptop forwards the dev server at `http://localhost:4321` (dev is never public; always tunneled).
- All devices (phone, laptop, desktop) continue to work as vault git clients, just pointed at the VPS host instead of `localhost`.

No architectural changes from Phase 1. This phase is environment, DNS, firewall, and secret handling.

## Why this is thin

The heavy lifting happened in 1a/1b/1c. Phase 2's job is to make the same system work behind a real domain with real TLS on a real VPS. Everything you need for that is already in the design:

- Env-var-driven port bindings (`${SSH_BIND:-127.0.0.1}` → `0.0.0.0` on the VPS).
- Caddy already auto-obtains certs when `DOMAIN` is a real host that resolves publicly.
- The autoblog wrapper already supports `--tunnel` for the dev server.
- sshd is already key-only and hardened.
- The single-image model means `docker compose up -d` is the deploy.

## Prerequisite

Phases 1a, 1b, and 1c are complete and running locally. The user has validated the full system (deploy, rollback, ingest, multi-device sync) against `localhost` before attempting VPS.

## Success criteria

- [ ] VPS provisioned with Docker + docker compose plugin; repo cloned; `.env` populated with Phase 2 overrides.
- [ ] DNS A record for `$DOMAIN` points at the VPS before Caddy first starts (required for Let's Encrypt).
- [ ] Firewall allows only: 22 (host sshd), 2222 (container sshd — primary), 80, 443 (Caddy). **Port 4321 is closed.**
- [ ] `docker compose up -d --wait` succeeds on the VPS.
- [ ] `https://$DOMAIN` serves the production site with a valid Let's Encrypt certificate.
- [ ] `ssh -p 2222 autoblog@$DOMAIN` drops into tmux with `/agent` as cwd.
- [ ] `autoblog --tunnel` from laptop forwards dev server to `http://localhost:4321`.
- [ ] Vault git push/pull from laptop and phone, pointed at `$DOMAIN:2222`, works.
- [ ] `lsof`-on-the-VPS confirms 4321 is bound to 127.0.0.1 only (not publicly reachable).
- [ ] fail2ban active and reporting from /var/log/auth.log.

## Files changed in this phase

No source files change. Phase 2 is fully covered by:

- `.env` on the VPS (the only place that differs from Phase 1)
- DNS records (out-of-band)
- Firewall rules (on the VPS OS, not in this repo)

The existing `docs/deploying.md` holds the runbook; this plan specifies what that file contains.

## Topology

```
Public internet
    │
    ├── 22   →  VPS host sshd              (emergency/debug; key-only; fail2ban)
    ├── 2222 →  container sshd             (primary interaction path; agent shell; git-over-SSH)
    ├── 80   →  Caddy (HTTP; auto-redirect to HTTPS)
    └── 443  →  Caddy (HTTPS; Let's Encrypt auto-TLS; prod site only)

NOT public:
    ×  4321  →  Astro dev (bound 127.0.0.1 on the VPS; reached via `ssh -L` from laptop)
```

## The two-sshd model on the VPS

Why two sshds? Because the VPS's host OS already runs its own sshd on port 22, and the autoblog container has its own sshd on container:22 (published as host:2222). They coexist:

- Host sshd on `:22` — exists for emergency/debugging at the VPS OS level (rebooting, inspecting docker state, reading logs when the container is unhealthy). You rarely use it day-to-day.
- Container sshd on `:2222` — the primary path. Every `autoblog` invocation, every `git clone`/`git push` against the vault, every agent session — all land here.

This is intentional, not a limitation. Trying to expose the container's sshd on host port 22 means fighting the host OS for the port, which is messy. Leaving the host's sshd on 22 and publishing the container's on 2222 keeps responsibilities clean.

## Implementation tasks

### Task 1 — Provision VPS

Pick a provider (GCE e2-small, DigitalOcean droplet, Hetzner CX11, etc.). Minimum spec:
- 2 GB RAM (Astro dev server + Node deps need breathing room)
- 20 GB disk
- Linux (Debian 12 or Ubuntu 22.04+ recommended; matches container base)

SSH in as root or a sudo user.

### Task 2 — Install Docker + compose

Follow Docker's official installation docs for your distro. Verify:

```bash
docker --version
docker compose version
```

### Task 3 — DNS

Create an A record pointing `$DOMAIN` (and optionally `www.$DOMAIN`) at the VPS public IP. **Do this before the first `docker compose up`** — Caddy will attempt to obtain a certificate for `$DOMAIN` on first start; if DNS isn't propagated, the cert request fails and you're stuck on the Let's Encrypt rate limit for that domain.

Verify from a neutral location:

```bash
dig +short $DOMAIN
```

Should return the VPS IP.

### Task 4 — Firewall (ufw)

```bash
sudo apt install -y ufw fail2ban
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # host sshd (emergency)
sudo ufw allow 2222/tcp     # container sshd (primary)
sudo ufw allow 80/tcp       # Caddy HTTP (auto-redirects to HTTPS)
sudo ufw allow 443/tcp      # Caddy HTTPS
sudo ufw enable
sudo ufw status verbose
```

Port 4321 is not listed. It must not be publicly reachable — the container publishes it to loopback only (`DEV_BIND=127.0.0.1`), so the firewall never sees it, but we leave it out of ufw as defense-in-depth.

### Task 5 — fail2ban

Default install includes an sshd jail that watches `/var/log/auth.log` and bans IPs with repeated failed logins.

```bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

fail2ban protects the host sshd on `:22`. The container sshd on `:2222` is inside docker — its auth failures don't hit the host's auth.log by default. Options:
- Accept this (key-only auth with `MaxAuthTries 3` + `LoginGraceTime 20` already hardens the container sshd; brute force is very slow).
- Or pipe container sshd logs to the host's fail2ban via a syslog driver. Out of scope for this plan; worth revisiting if you see auth.log noise.

### Task 6 — Clone repo + configure .env

```bash
cd /opt
sudo git clone <repo-url> autoblog
sudo chown -R $USER:$USER autoblog
cd autoblog
cp .env.example .env
```

Edit `.env`:

```bash
# Required
ANTHROPIC_API_KEY=sk-ant-...
SSH_PUBLIC_KEY="ssh-ed25519 AAAA...laptop
ssh-ed25519 BBBB...desktop
ssh-ed25519 CCCC...phone"
TIMEZONE=America/Los_Angeles

# Phase 2 overrides (THIS IS THE ONLY DIFFERENCE FROM PHASE 1)
DOMAIN=your-real-domain.com
SSH_BIND=0.0.0.0             # public SSH on container port (host :2222)
DEV_BIND=127.0.0.1           # KEEP loopback. Never public. Reached via ssh -L.
CADDY_BIND=0.0.0.0
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
```

Notes:
- `SSH_BIND=0.0.0.0` applies to the `:2222:22` mapping. The VPS's host sshd on host:22 is untouched.
- `DEV_BIND=127.0.0.1` is critical. Do not change it. The dev server is reached from your laptop via SSH tunnel, not by public binding.

### Task 7 — First deploy

```bash
cd /opt/autoblog
./scripts/install.sh   # runs docker compose up -d --wait
```

Watch the logs:

```bash
docker compose logs -f
```

First-boot time: 3–10 minutes (as in Phase 1 — npm install + initial Astro build happen at container first boot; they haven't happened on this volume yet). Also watch for Caddy obtaining its Let's Encrypt cert — you'll see `certificate obtained successfully` or similar.

If the cert fails: check DNS, check port 80 is reachable from the internet, check `DOMAIN` is correct in `.env`.

### Task 8 — Verify

On the VPS:

```bash
# 1. All expected bindings
sudo lsof -iTCP -sTCP:LISTEN -P | grep -E ':(22|2222|80|443|4321)'
# Expected:
#   sshd (host)    *:22
#   docker-proxy   *:2222                   (from SSH_BIND=0.0.0.0)
#   docker-proxy   127.0.0.1:4321          (from DEV_BIND=127.0.0.1)
#   docker-proxy   *:80
#   docker-proxy   *:443
```

From your laptop:

```bash
# 2. HTTPS prod site works
curl -sI https://$DOMAIN | head -3
# Expected: HTTP/2 200; cert issued by Let's Encrypt

# 3. SSH into container
ssh -p 2222 autoblog@$DOMAIN "echo ok && pwd"
# Expected: "ok" and (interactive) /agent

# 4. Vault git clone reaches remote
git clone ssh://autoblog@$DOMAIN:2222/vault-remote.git /tmp/vault-vps-test
ls /tmp/vault-vps-test
# Expected: vault content

# 5. Dev tunnel works
AUTOBLOG_HOST=$DOMAIN autoblog --tunnel
# (leaves you in tmux; in another terminal on your laptop:)
curl -sI http://localhost:4321 | head -3
# Expected: HTTP/1.1 200 from Astro
```

### Task 9 — Point existing device clones at the VPS

After laptop/desktop/phone were set up against `localhost` in Phase 1c, update their Obsidian Git remotes:

**Laptop / desktop:**
```bash
cd ~/Documents/autoblog-vault
git remote set-url origin ssh://autoblog@$DOMAIN:2222/vault-remote.git
git pull
```

**Phone:** update the remote URL in the Obsidian Git plugin settings; point at `ssh://autoblog@$DOMAIN:2222/vault-remote.git`.

Because the vault history is the same (you pushed the vault state from your laptop clone to the VPS during the first vault push — or the VPS is a fresh seed you'll re-push local content to), the clones pick up and resume.

**Important:** if the VPS vault is a freshly-seeded empty vault (because first `docker compose up` ran the bootstrap), you'll want to push your local vault's full history up to it first:

```bash
# from your laptop, on the old localhost-pointed clone
cd ~/Documents/autoblog-vault
git remote add vps ssh://autoblog@$DOMAIN:2222/vault-remote.git
git push --force vps main         # one-time; replaces VPS seed with local history
git remote set-url origin ssh://autoblog@$DOMAIN:2222/vault-remote.git
git remote remove vps
```

Force-pushing is appropriate exactly once here: you're replacing the VPS's initial-seed commit with your richer local history. Never force-push after this setup.

Do the same for the site volume if you care about preserving your Phase 1 site history — or start fresh and re-author on the VPS.

### Task 10 — Backups (manual for now)

Set a calendar reminder weekly:

```bash
ssh <vps-host>
cd /opt/autoblog
docker run --rm \
  -v autoblog_vault:/src/vault:ro \
  -v autoblog_vault_remote:/src/vault-remote:ro \
  -v autoblog_site:/src/site:ro \
  -v $(pwd):/dst \
  busybox tar czf /dst/backup-$(date +%Y%m%d).tgz -C /src .
# copy the .tgz to your laptop via scp
```

Automation (cron on the VPS, or S3 upload) is out of scope but straightforward to add once the manual flow is working.

### Task 11 — Documentation

Update `docs/deploying.md` to contain the Phase 2 runbook above. Keep the tone operational (step-by-step, with the expected outputs at each step), not narrative.

Keep the existing `docs/autoblog-overview.md` unchanged — it's architecture-level and describes Phase 2 in principle. `deploying.md` is the step-by-step.

## Final checklist

- [ ] VPS provisioned, Docker installed.
- [ ] DNS A record for `$DOMAIN` resolves publicly.
- [ ] ufw allows only 22, 2222, 80, 443.
- [ ] fail2ban active.
- [ ] `.env` on VPS has `SSH_BIND=0.0.0.0`, `CADDY_BIND=0.0.0.0`, `CADDY_HTTP_PORT=80`, `CADDY_HTTPS_PORT=443`, `DEV_BIND=127.0.0.1`.
- [ ] `docker compose up -d --wait` succeeds; Caddy obtains a Let's Encrypt cert.
- [ ] `https://$DOMAIN` returns the prod site with a valid cert.
- [ ] `ssh -p 2222 autoblog@$DOMAIN` works.
- [ ] `autoblog --tunnel` forwards dev server.
- [ ] `lsof` on VPS confirms 4321 is 127.0.0.1-bound, NOT `*:4321`.
- [ ] Vault git clients (laptop, desktop, phone) pointed at VPS, clone/pull/push works.
- [ ] `docs/deploying.md` contains the full runbook.
- [ ] Backup procedure documented and run once manually.

## Anti-patterns to avoid

- Skipping DNS propagation before first `docker compose up`. Failed Let's Encrypt cert = rate-limit lockout.
- Setting `DEV_BIND=0.0.0.0`. The dev server is never public. Always tunnel.
- Exposing the container sshd on host port 22. The host OS owns `:22`. Leave it alone.
- Omitting the IP bind from port mappings on the VPS. Fail-safe default of `127.0.0.1` catches a forgotten `SSH_BIND` — but don't rely on it; set it explicitly.
- Force-pushing to vault-remote.git after initial setup. The agent and multiple devices are downstream clones; force-push breaks them.
- Enabling root ssh. Not needed for anything this system does.
- Running fail2ban against the container sshd without wiring its logs to the host first. Otherwise it's no-op on container auth failures.
- Adding Tailscale or any other sidecar to "simplify" access. SSH + `-L` meets the requirement.

## Out of scope

- Automated backups (S3, Glacier, restic). Manual weekly backups for now.
- CI/CD (GitHub Actions auto-deploy on push). Deploys are on-demand by the agent.
- Terraform / IaC for VPS provisioning. Manual one-time setup.
- Multi-environment (staging + prod). Single environment.
- Monitoring / alerting. Add when you miss something.

## Plan confidence

**9/10** for one-pass implementation. The system is the same image that's been validated in Phase 1 — only `.env` differs. The external dependencies (DNS, Caddy+Let's Encrypt, ufw, fail2ban) are standard building blocks with well-known failure modes. The two places where iteration is likely:

- Let's Encrypt cert acquisition on first boot (fixable in all cases by verifying DNS + port 80 reachability).
- Phone / multi-device SSH key setup against the public hostname (minor — same keys, different remote URL).
