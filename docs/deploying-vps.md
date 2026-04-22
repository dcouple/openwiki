# Deploying openwiki on a VPS

Minimum-steps guide to go from a fresh VPS to a running openwiki you can reach from Obsidian on your laptop. The last section is optional — it adds a custom domain with automatic HTTPS.

Same image and `compose.yml` as the laptop guide. Only `.env` differs.

## What you'll end up with

- `openwiki` container on `<vm-ip>:2222` (SSH + git-over-SSH for the vault)
- Caddy serving the published site on `http://<vm-ip>` (port 80)
- An Obsidian vault on your laptop that syncs to the container over SSH
- Daily agent skills/memory persisted in Docker volumes on the VM

## Prerequisites

- A fresh VPS (Debian 12 or Ubuntu 22.04+) with a public IP and root/sudo access
- An SSH key on your laptop — `ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"` if you don't have one
- **Claude Code auth** — either a Claude Pro/Max subscription or an Anthropic API key
- Obsidian on your laptop — <https://obsidian.md/download>
- *(Optional)* a domain you control, if you want HTTPS at `https://yourdomain.com`

## 1. SSH into the VM

```bash
ssh root@<vm-ip>
# or: ssh <non-root-user>@<vm-ip>
```

From here on, all commands run on the VM unless noted otherwise.

## 2. Clone the repo

```bash
sudo mkdir -p /opt && sudo chown "$USER" /opt
git clone https://github.com/dcouple/openwiki /opt/openwiki
cd /opt/openwiki
```

## 3. Run the provision script

One shot: installs Docker + compose, sets up `ufw` (allow 22, 2222, 80, 443), enables `fail2ban`, installs `jq`, symlinks `openwiki` onto your `PATH`, and seeds `.env` from `.env.example`. Idempotent — safe to re-run.

```bash
sudo bash scripts/provision-vps.sh
```

The script stops after seeding `.env` so you can edit it.

## 4. Edit `.env`

```bash
openwiki edit-env    # opens .env in $EDITOR
```

Set these values:

```
SSH_PUBLIC_KEY="<paste your laptop's ~/.ssh/id_ed25519.pub here>"

# Claude Code auth — pick ONE:
#   (A) leave blank; you'll run `/login` on first boot (Pro/Max subscription)
#   (B) set ANTHROPIC_API_KEY=sk-ant-... for per-token API billing
ANTHROPIC_API_KEY=

# Phase 2 overrides — uncomment these so the VM actually accepts connections:
SSH_BIND=0.0.0.0
CADDY_BIND=0.0.0.0
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
```

Leave `DEV_BIND=127.0.0.1` — the Astro dev server is reached via SSH tunnel from your laptop, never publicly exposed.

Leave `DOMAIN=localhost` for now. You'll change it in the optional domain section.

To copy your laptop key to the clipboard on macOS: `pbcopy < ~/.ssh/id_ed25519.pub`.

## 5. Start the stack

```bash
openwiki up
```

First boot takes 3–10 minutes — the container runs `npm install` and an initial Astro build on first mount of its volumes. Tail logs while it warms up:

```bash
openwiki logs
```

The compose health check flips to healthy when the agent is ready. Confirm with `openwiki status`.

The public site is now reachable from anywhere at `http://<vm-ip>`.

## 6. Connect to the agent from your laptop

From your **laptop** (not the VM):

```bash
ssh -p 2222 -t autoblog@<vm-ip> "tmux new-session -A -s main -c /agent"
```

Inside the tmux session:

```bash
claude
```

If you left `ANTHROPIC_API_KEY` blank, Claude's first prompt will be `/login` — it prints a URL and a code; open the URL in your laptop browser, sign in to Claude.ai, paste the code back. The credential persists in the `openwiki_claude` volume.

Detach tmux with `Ctrl-b d`. Reattach any time with the same `ssh` command — same session, same Claude history.

## 7. Set up Obsidian on your laptop

The container hosts a bare vault repo at `/vault-remote.git` served over SSH on port 2222. You clone it onto your laptop and point Obsidian at the clone.

From your **laptop**:

```bash
git clone ssh://autoblog@<vm-ip>:2222/vault-remote.git ~/Documents/openwiki-vault
```

Then in Obsidian:

1. **File → Open Vault → Open folder as vault** → select `~/Documents/openwiki-vault`.
2. **Settings → Community plugins → Browse** → search *Obsidian Git* → Install + Enable.
3. Open *Obsidian Git* settings and set:
   - Commit message on auto-backup: `vault: {{date}}`
   - Auto-backup interval: `5` minutes
   - Pull on start: **ON**
   - Pull on auto-backup: **ON**

You can now drop sources into `raw/` from Obsidian and the agent will see them the next time it pulls. For phone setup (iOS/Android), see [`vault-sync.md`](./vault-sync.md).

## Daily operations

All run on the VM:

```bash
openwiki status              # container health + volume names
openwiki logs openwiki       # tail agent logs
openwiki logs caddy          # tail web logs
openwiki restart             # pick up .env changes
openwiki update              # git pull + rebuild
openwiki backup              # tar the user-content volumes
openwiki help                # full command list
```

Vault, site, agent skills, and Claude credentials all live in named Docker volumes. `openwiki down` keeps state; only `docker compose down -v` erases it.

---

## (Optional) 8. Wire up a custom domain with HTTPS

Do this after the HTTP-only setup above is working.

### a. Point DNS at the VM

At your registrar (Cloudflare, Namecheap, Route 53, etc.), create an **A record**:

```
yourdomain.com  A  <vm-ip>
```

If you're using Cloudflare, set the record to **DNS only** (grey cloud) for the first boot, so Caddy can complete the Let's Encrypt HTTP-01 challenge. You can turn the proxy on later.

Wait until `dig +short yourdomain.com` returns the VM IP from a neutral network before continuing. If you start Caddy before DNS resolves, Let's Encrypt will fail the challenge and may rate-limit the domain for an hour.

### b. Update `.env`

```bash
openwiki edit-env
```

```
DOMAIN=yourdomain.com
```

### c. Switch the Caddyfile to auto-TLS

Edit `/opt/openwiki/Caddyfile` on the VM and replace the `:80` site block with your domain. Caddy provisions Let's Encrypt certs automatically when the site block is a hostname.

```caddyfile
{$DOMAIN} {
    root * /srv/site/prod/dist
    file_server
    try_files {path} {path}/ /index.html
    encode gzip
    header / Cache-Control "public, max-age=300"
}
```

### d. Restart and watch the cert issue

```bash
openwiki restart
openwiki logs caddy
```

Look for `certificate obtained successfully`. First issuance takes 10–60 seconds.

### e. Verify from your laptop

```bash
curl -sI https://yourdomain.com | head -3
# Expect: HTTP/2 200, server: Caddy, Let's Encrypt cert
```

You can also now reach the agent at `ssh -p 2222 autoblog@yourdomain.com` and update your Obsidian remote to use the hostname instead of the IP.

## Troubleshooting

- **`openwiki: command not found`** — `provision-vps.sh` installs the symlink at `/usr/local/bin/openwiki`. If it's missing, run the script again or call `./bin/openwiki` from the repo root.
- **`ssh: connection refused` on port 2222 from your laptop** — `SSH_BIND` is still `127.0.0.1`. Set `SSH_BIND=0.0.0.0` in `.env` and run `openwiki restart`.
- **`http://<vm-ip>` doesn't load** — check `CADDY_BIND=0.0.0.0`, `CADDY_HTTP_PORT=80`, and that `ufw` allows port 80 (`sudo ufw status`).
- **SSH asks for a password** — your public key isn't in `.env`, or you changed it after first boot. Re-check `SSH_PUBLIC_KEY`, then `openwiki restart`.
- **`certificate obtained successfully` never appears** — DNS isn't propagated yet, or the A record points somewhere else. `dig +short yourdomain.com` from a neutral network must return the VM IP. If you're on Cloudflare, make sure the record is grey-clouded (DNS only) for first issuance.
- **First SSH prompts you to verify a host key fingerprint** — expected. Type `yes`. The fingerprint is stable across container restarts because sshd host keys live in the `openwiki_ssh` volume.

## What's next

- Multi-device vault sync (phone, desktop, second laptop): [`vault-sync.md`](./vault-sync.md)
- Architecture deep-dive: [`autoblog-overview.md`](./autoblog-overview.md)
- GCP-specific variant with a separate data disk and daily snapshots: [`deploying-gcp.md`](./deploying-gcp.md)
