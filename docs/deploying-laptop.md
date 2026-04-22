# Running openwiki on a laptop (macOS)

Local development guide for hacking on openwiki itself. On a VPS the canonical flow is [`deploying-vps.md`](./deploying-vps.md)'s one-line installer; on macOS the installer **does not run** — it assumes Debian/Ubuntu, `ufw`, `fail2ban`, and `systemctl`. So on a laptop you clone the repo, set up `.env` by hand, and use `docker compose` directly.

Honest note: this page is for developers. If you just want to run openwiki, use a cheap VPS and the installer — the laptop path has more moving parts and exists mainly so contributors can test changes.

On Apple Silicon and Intel Macs alike, Docker Desktop handles architecture transparently.

## What you get

- `openwiki` container on `127.0.0.1:2222` (SSH + git-over-SSH)
- Astro dev server on `http://localhost:4321` (all content, including drafts)
- Caddy serving the prod site on `http://localhost:8080` (published pages only)
- A bare vault remote you clone from any device with Obsidian + Obsidian Git

All bindings are loopback by default — nothing is reachable from your LAN.

## 1. Prerequisites

- **Docker Desktop for Mac** — <https://docs.docker.com/desktop/install/mac-install/>
- **git** — included with Xcode Command Line Tools (`xcode-select --install`)
- **jq** — `brew install jq` (used by the `openwiki` CLI)
- **An SSH key** — if you don't have one: `ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"`
- **Claude Code auth** — either a **Claude Pro/Max subscription** (<https://claude.ai>) or an **Anthropic API key** (<https://console.anthropic.com>).

Start Docker Desktop and confirm it's running:

```bash
docker --version
docker compose version
```

## 2. Clone the repo

```bash
git clone https://github.com/dcouple/openwiki ~/openwiki
cd ~/openwiki
```

## 3. Put `compose.yml` at the repo root

In the image-first layout, `compose.yml` lives at `autoblog/host-files/compose.yml` (it's baked into the image and extracted by the installer on a VPS). For the laptop dev flow you want it at the repo root so `compose.dev.yml`'s relative paths (`build: ./autoblog`) resolve correctly.

Simplest approach — copy it:

```bash
cp autoblog/host-files/compose.yml ./compose.yml
```

`compose.yml` at the repo root is already gitignored in this layout; the copy is local to your checkout.

## 4. Write a minimal `.env`

Create `.env` at the repo root with exactly these values:

```
COMPOSE_PROJECT_NAME=openwiki
SSH_PUBLIC_KEY="<paste the contents of ~/.ssh/id_ed25519.pub>"
TIMEZONE=UTC
ANTHROPIC_API_KEY=
DOMAIN=localhost
SSH_BIND=127.0.0.1
DEV_BIND=127.0.0.1
CADDY_BIND=127.0.0.1
CADDY_HTTP_PORT=8080
CADDY_HTTPS_PORT=8443
```

Notes:

- `pbcopy < ~/.ssh/id_ed25519.pub` puts your public key on the clipboard.
- Leave `ANTHROPIC_API_KEY=` blank to use your Claude Pro/Max subscription (you'll run `/login` inside the agent on first boot). Or set `ANTHROPIC_API_KEY=sk-ant-...` for per-token API billing.
- All three `*_BIND=127.0.0.1` values keep everything on loopback. Don't change them for local dev.

## 5. Render the Caddyfile

`compose.yml` expects a literal `Caddyfile` at `./Caddyfile`. The template is at `autoblog/host-files/Caddyfile.template`. For `DOMAIN=localhost` on a laptop, write a plain HTTP-only Caddyfile:

```bash
cat > Caddyfile <<'EOF'
:80 {
    root * /srv/site/prod/dist
    file_server
    try_files {path} {path}/ /index.html
    encode gzip
    header / Cache-Control "public, max-age=300"
}
EOF
```

(Inside the container Caddy listens on `:80`; `CADDY_HTTP_PORT=8080` maps that to your laptop's `8080`.)

## 6. Build and start the stack

`compose.dev.yml` overrides the image reference so docker compose builds from `./autoblog` instead of pulling from GHCR:

```bash
docker compose -f compose.yml -f compose.dev.yml up -d --build --wait
```

Tail logs while it warms up (first boot takes a few seconds now that `node_modules` and `dist` are baked into the image):

```bash
docker compose -f compose.yml -f compose.dev.yml logs -f
```

## 7. Put the `openwiki` CLI on your PATH

The `openwiki` CLI lives in the image at `/opt/openwiki/openwiki` and in source at `autoblog/host-files/openwiki`. For the laptop dev flow, symlink the source copy so `openwiki` stays in sync as you edit it:

```bash
sudo ln -sf "$PWD/autoblog/host-files/openwiki" /usr/local/bin/openwiki
INSTALL_DIR="$PWD" openwiki status
```

The CLI defaults `INSTALL_DIR=/opt/openwiki`; on a laptop you override it to your checkout. Export it in your shell if you'll use the CLI frequently:

```bash
echo 'export INSTALL_DIR="$HOME/openwiki"' >> ~/.zshrc
```

(Alternative: extract the CLI from the built image with `docker cp $(docker create openwiki:dev):/opt/openwiki/openwiki ./openwiki`. The symlink form is simpler for active development.)

## 8. Connect to the agent

```bash
openwiki ssh
```

That runs `ssh -p 2222 -t autoblog@localhost "tmux new-session -A -s main -c /agent"`. Inside the tmux session:

```bash
claude         # start or resume a conversation with the agent
```

If you left `ANTHROPIC_API_KEY` blank, the first prompt inside Claude will be to run `/login` — it prints a URL and a code; open the URL in your Mac browser, sign in to Claude.ai, paste the code back. The credential persists in the `openwiki_claude` volume, so you only do it once.

Detach from tmux with `Ctrl-b d`. Reattach by running `openwiki ssh` again — same session, same Claude history.

## 9. See the site

- Dev (everything, including drafts): <http://localhost:4321> (forward from the VM with `openwiki ssh --tunnel` if you're testing a VM-hosted instance from your laptop)
- Prod (published only): <http://localhost:8080>

## 10. Connect Obsidian to the vault (optional)

```bash
git clone ssh://autoblog@localhost:2222/vault-remote.git ~/Documents/openwiki-vault
```

Open `~/Documents/openwiki-vault` as an Obsidian vault and enable the Obsidian Git community plugin with auto-commit/pull/push. Full multi-device setup (desktop, phone) and plugin config are in [`vault-sync.md`](./vault-sync.md).

## Daily operations

```bash
# stop
docker compose -f compose.yml -f compose.dev.yml stop

# start again
docker compose -f compose.yml -f compose.dev.yml start

# tail logs
docker compose -f compose.yml -f compose.dev.yml logs -f

# rebuild image after editing the Dockerfile
docker compose -f compose.yml -f compose.dev.yml up -d --build

# wipe and start over (DESTROYS vault, site, agent state)
docker compose -f compose.yml -f compose.dev.yml down -v
docker compose -f compose.yml -f compose.dev.yml up -d --build --wait
```

Everything the agent reads or writes (vault, site, skills, memory) lives in named Docker volumes. Stopping the container keeps all state; only `... down -v` erases it.

## Troubleshooting

- **`ssh: connect to host localhost port 2222: Connection refused`** — container isn't healthy yet. `docker compose ps` to check status; `docker compose logs openwiki` to see why.
- **First connect prompts you to verify a host key fingerprint** — expected. Type `yes`. The fingerprint is stable across container restarts because sshd keys live in a named volume.
- **SSH asks for a password** — your public key isn't in `.env`, or you changed it after first boot. Re-check `SSH_PUBLIC_KEY`, then `docker compose restart openwiki`.
- **Claude shows "API Usage Billing" but you wanted subscription** — `ANTHROPIC_API_KEY` is still set. Comment it out in `.env` and run `docker compose up -d --force-recreate`, then `/login` fresh.
- **`http://localhost:8080` is already taken by another app** — change `CADDY_HTTP_PORT` in `.env` to e.g. `8090`, then `docker compose up -d`.
- **Docker Desktop warns about low resources** — bump CPU/RAM in Settings → Resources. 2 CPU / 4 GB is comfortable.

## What changes on a VPS

Nothing in the code. Only the deploy path: the [VPS guide](./deploying-vps.md) uses the one-line `install.sh` (Linux-only), which handles firewall, fail2ban, DNS precheck, and auto-TLS. Your laptop setup keeps working unchanged.
