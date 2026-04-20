# Running autoblog on a laptop (macOS)

Minimum-steps guide for a local Phase 1 install. The same image and `compose.yml` run in Phase 2 on a VPS — only `.env` differs.

On Apple Silicon and Intel Macs alike, Docker Desktop handles architecture transparently.

## What you get

- `autoblog` container on `127.0.0.1:2222` (SSH + git-over-SSH)
- Astro dev server on `http://localhost:4321` (all content, including drafts)
- Caddy serving the prod site on `http://localhost:8080` (published pages only)
- A bare vault remote you clone from any device with Obsidian + Obsidian Git

All bindings are loopback by default — nothing is reachable from your LAN.

## Prerequisites

- **Docker Desktop for Mac** — <https://docs.docker.com/desktop/install/mac-install/>
- **git** — included with Xcode Command Line Tools (`xcode-select --install`)
- **An SSH key** — if you don't have one: `ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"`
- **An Anthropic API key** — from <https://console.anthropic.com/>
- **Obsidian** (optional, for the vault) — <https://obsidian.md/download>

Start Docker Desktop and confirm it's running:

```bash
docker --version
docker compose version
```

## 1. Clone the repo

```bash
git clone https://github.com/<you>/autoblog ~/repos/autoblog
cd ~/repos/autoblog
```

## 2. Configure `.env`

```bash
cp .env.example .env
$EDITOR .env
```

Set these two values; leave everything else at defaults:

```
ANTHROPIC_API_KEY=sk-ant-...
SSH_PUBLIC_KEY="<paste the contents of ~/.ssh/id_ed25519.pub>"
```

Get your public key quickly:

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

The default bindings (`SSH_BIND=127.0.0.1`, `DEV_BIND=127.0.0.1`, `CADDY_BIND=127.0.0.1`) keep everything on loopback. Don't change them for local dev.

## 3. Start it

```bash
./scripts/install.sh
```

First boot takes 3–10 minutes — the container runs `npm install` and an initial Astro build on first mount of its volumes. Watch progress:

```bash
docker compose logs -f
```

The compose health check flips to healthy when the agent is ready.

## 4. Connect to the agent

```bash
./bin/autoblog
```

That wrapper runs `ssh -p 2222 -t autoblog@localhost "tmux new-session -A -s main -c /agent"`. Inside the tmux session:

```bash
claude         # start or resume a conversation with the agent
```

Detach from tmux with `Ctrl-b d`. Reattach by running `./bin/autoblog` again — same session, same Claude history.

Optional: put the wrapper on your PATH.

```bash
ln -s "$PWD/bin/autoblog" /usr/local/bin/autoblog
autoblog
```

## 5. See the site

- Dev (everything): <http://localhost:4321>
- Prod (published only): <http://localhost:8080>

## 6. Connect Obsidian to the vault (optional)

The container holds a bare vault remote you clone locally and open in Obsidian:

```bash
git clone ssh://autoblog@localhost:2222/vault-remote.git ~/Documents/autoblog-vault
```

Then open `~/Documents/autoblog-vault` as an Obsidian vault and enable the Obsidian Git community plugin with auto-commit/pull/push.

Full multi-device setup (desktop, phone) and plugin config are in `docs/vault-sync.md`.

## Daily operations

```bash
# stop
docker compose stop

# start again
docker compose start

# tail logs
docker compose logs -f

# rebuild image after editing the Dockerfile
docker compose up -d --build

# wipe and start over (DESTROYS vault, site, agent state)
docker compose down -v
./scripts/install.sh
```

Everything the agent reads or writes (vault, site, skills, memory) lives in named Docker volumes. Restarting the container keeps all state; only `docker compose down -v` erases it.

## Troubleshooting

- **`ssh: connect to host localhost port 2222: Connection refused`** — container isn't healthy yet. `docker compose ps` to check status; `docker compose logs autoblog` to see why.
- **SSH asks for a password** — your public key isn't in `.env`, or you changed it after first boot. Re-check `SSH_PUBLIC_KEY`, then `docker compose restart autoblog`.
- **`http://localhost:8080` shows a placeholder** — expected until Phase 1b's deploy skill produces a real build.
- **Docker Desktop warns about low resources** — bump CPU/RAM in Settings → Resources. 2 CPU / 4 GB is comfortable.

## What changes on a VPS

Nothing in the code. Only `.env` (see `docs/deploying.md` for the generic flow, `docs/deploying-gcp.md` for GCP-specific steps). Your laptop setup keeps working unchanged.
