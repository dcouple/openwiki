# Deploying openwiki on a VPS

Minimum-steps guide to go from a fresh VPS to a running openwiki you can reach from Obsidian on your laptop. The installer is the canonical flow — one command, two minutes, three interactive prompts.

## What you'll end up with

- `openwiki` container on `<vm-ip>:2222` (SSH + git-over-SSH for the vault)
- Caddy serving the published site on `http://<vm-ip>` (port 80), or at your domain with automatic HTTPS if you configure one
- An Obsidian vault on your laptop that syncs to the container over SSH
- Daily agent skills/memory persisted in Docker volumes on the VM

## 1. Prerequisites

- A fresh VPS (Debian 12 or Ubuntu 22.04+) with a public IP and `sudo` access
- An **SSH public key** on your laptop — `ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"` if you don't have one. Copy it with `pbcopy < ~/.ssh/id_ed25519.pub` (macOS) or `xclip -selection clipboard < ~/.ssh/id_ed25519.pub` (Linux).
- **Claude Code auth** — either a Claude Pro/Max subscription (log in at first boot via `/login`) **or** an Anthropic API key.
- **(Optional)** a domain you control, with an **A record** pointing at the VPS public IP. The installer will refuse to auto-TLS against a hostname whose DNS doesn't resolve to the VM — it'll offer to use Let's Encrypt staging or fall back to plain HTTP until DNS is ready.

## 2. Install

SSH into the VPS (`ssh root@<vm-ip>` or `ssh <user>@<vm-ip>`), then run:

```bash
curl -fsSL https://raw.githubusercontent.com/dcouple/openwiki/main/install.sh -o /tmp/openwiki-install.sh
sudo bash /tmp/openwiki-install.sh
```

The installer is idempotent and takes **under two minutes** on a warm VM. It:

1. Detects Debian/Ubuntu and refuses to run elsewhere.
2. Migrates a prior git-clone install at `/opt/openwiki` (prompts first; renames it to `/opt/openwiki.legacy-<timestamp>`; volumes survive).
3. Installs Docker, Docker Compose, `jq`, `ufw` (deny-incoming, allows host sshd + `2222` + `80` + `443`), and `fail2ban`.
4. Pulls the `ghcr.io/dcouple/openwiki:latest` image and extracts the host config (`compose.yml`, `Caddyfile.template`, `openwiki` CLI) into `/opt/openwiki/`, symlinking the CLI to `/usr/local/bin/openwiki`.
5. Prompts you for **three things**:
   - **Domain** — blank for HTTP-only at the IP, or `yourdomain.com` for automatic HTTPS. Blank is fine; you can add a domain later with `sudo openwiki set-domain`.
   - **SSH public key** — paste your laptop's `~/.ssh/id_ed25519.pub` on one line.
   - **Anthropic API key** — blank to use a Claude Pro/Max subscription (you'll run `/login` on first boot), or `sk-ant-...` for per-token API billing.
6. Renders `/opt/openwiki/Caddyfile` from the template and the chosen domain, writes `/opt/openwiki/.env` (mode 600, root:root), and starts the stack with `docker compose up -d --wait`.

### Pinning a specific version

```bash
sudo VERSION=v0.1.0 bash /tmp/openwiki-install.sh
```

### Reconfiguring `.env` in place

If you want to re-enter the three prompts (e.g., to change the domain or the SSH key) without a full reinstall, re-run with `RECONFIGURE=1`:

```bash
sudo RECONFIGURE=1 bash /tmp/openwiki-install.sh
```

## 3. Connect to the agent

From your **laptop** (not the VM):

```bash
ssh -p 2222 -t autoblog@<vm-ip> "tmux new-session -A -s main -c /agent"
```

Or, equivalently, using the wrapper (copy `openwiki` off the VM to your laptop, or just use plain `ssh`):

```bash
openwiki ssh             # opens the agent tmux session
openwiki ssh --tunnel    # also forwards localhost:4321 -> VM dev server
```

Inside the tmux session:

```bash
claude
```

If you left `ANTHROPIC_API_KEY` blank, Claude's first prompt will be `/login` — it prints a URL and a code; open the URL in your laptop browser, sign in to Claude.ai, paste the code back. The credential persists in the `openwiki_claude` volume, so you only do it once.

Detach with `Ctrl-b d`. Reattach any time by running the same SSH command — same session, same Claude history.

The first SSH connection prompts you to verify a host key fingerprint. Type `yes`. The fingerprint is stable across container restarts because sshd host keys live in the `openwiki_ssh` volume.

## 4. (Optional) Set up Obsidian on your laptop

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

## 5. Changing the domain

To add a domain after an HTTP-only install, or to switch domains later:

1. Create / update the DNS A record so `yourdomain.com` → `<vm-ip>`. If you're on Cloudflare, grey-cloud the record (DNS only) for first issuance so Caddy can complete the Let's Encrypt HTTP-01 challenge.
2. Verify from a neutral network: `dig +short yourdomain.com` must return the VM IP.
3. On the VM:

   ```bash
   sudo openwiki set-domain yourdomain.com
   ```

   This re-renders `Caddyfile` from `Caddyfile.template`, updates `DOMAIN` in `.env`, and restarts **only** the caddy container (no agent downtime).

Watch the cert issue with `openwiki logs caddy`; first issuance takes 10–60 seconds. Confirm from your laptop with `curl -sI https://yourdomain.com | head -3`.

## 6. Updates

```bash
openwiki update --check    # pull :latest, diff local image IDs, report
openwiki update            # pull, atomically swap host files, restart
```

Volumes are preserved across updates; only the image and the `/opt/openwiki/{compose.yml,Caddyfile.template,openwiki}` host files are replaced.

To pin a specific version, edit `/opt/openwiki/compose.yml` and change the `image:` line (e.g., `ghcr.io/dcouple/openwiki:v0.1.0`), then `openwiki update`.

## 7. Backups

```bash
openwiki backup                 # tar the user-content volumes to ./backups/
openwiki backup restore <file>  # restore from a prior archive
```

Back up the resulting tarballs off the VM — they're the only thing that can't be re-derived from the image.

## Daily operations

All run on the VM:

```bash
openwiki status              # container health + volume names
openwiki logs openwiki       # tail agent logs
openwiki logs caddy          # tail web logs
openwiki restart             # pick up .env changes
openwiki edit-env            # open /opt/openwiki/.env in $EDITOR
openwiki set-domain <name>   # swap domain + restart caddy
openwiki update              # pull new image + swap host files + restart
openwiki backup              # tar the user-content volumes
openwiki help                # full command list
```

Vault, site, agent skills, and Claude credentials all live in named Docker volumes. `openwiki down` keeps state; only `docker compose down -v` (from `/opt/openwiki`) erases it.

## Troubleshooting

- **`openwiki: command not found`** — the installer symlinks `/opt/openwiki/openwiki` to `/usr/local/bin/openwiki`. If it's missing, re-run the installer or use the absolute path `/opt/openwiki/openwiki`.
- **`http://<vm-ip>` doesn't load** — `ufw status` should show `80/tcp ALLOW`. If not, re-run the installer; it is idempotent.
- **SSH to port 2222 asks for a password** — your public key didn't make it into `.env`. `sudo openwiki edit-env`, fix `SSH_PUBLIC_KEY`, then `openwiki restart`.
- **`certificate obtained successfully` never appears** — DNS isn't propagated yet, or the A record points somewhere else. `dig +short yourdomain.com` from a neutral network must return the VM IP. If you're on Cloudflare, grey-cloud the record for first issuance. The installer's DNS precheck catches this up-front — re-run with `RECONFIGURE=1` and pick the `[s]` staging option while you iterate.
- **First SSH prompts you to verify a host key fingerprint** — expected. Type `yes`. The fingerprint is stable across container restarts because sshd host keys live in the `openwiki_ssh` volume.

## What's next

- Multi-device vault sync (phone, desktop, second laptop): [`vault-sync.md`](./vault-sync.md)
- Architecture deep-dive: [`autoblog-overview.md`](./autoblog-overview.md)
- GCP-specific variant with a separate data disk and daily snapshots: [`deploying-gcp.md`](./deploying-gcp.md)
