# autoblog Phase 1a — Container Scaffold

## Overview

The smallest thing that proves the runtime shape is correct. At the end of this phase:

- `docker compose up -d --wait` brings up two services: `autoblog` (sshd + tmux + claude CLI) and `caddy` (serving a placeholder static page).
- `ssh -p 2222 autoblog@localhost` drops you into a tmux session at `/agent`.
- Running `claude` inside the container works — reads `CLAUDE.md`, has `ANTHROPIC_API_KEY` available.
- `curl http://localhost:8080` returns a "hello from autoblog — Phase 1a" page served by Caddy.
- No Astro, no vault, no site worktrees, no ingest. Those come in 1b and 1c.

This phase establishes the durable runtime (Dockerfile, entrypoint, bootstrap, sshd config, env-driven port bindings, laptop wrapper) that 1b and 1c extend without rewriting.

## Why do this first, alone

Container-boot debugging has a lot of surface area (volume mounts, sshd host keys, env delivery, tmux auto-attach). Isolating it from Astro/vault/skills means a failure here is unambiguous and fixable without wading through unrelated concerns.

## Success criteria

- [ ] `docker compose config` validates cleanly with default `.env.example` values.
- [ ] `docker compose build` succeeds.
- [ ] `docker compose up -d --wait` brings both services healthy within 60s (no Astro build on first boot yet — this phase is fast).
- [ ] All host-side ports bind to `127.0.0.1` only. `lsof -iTCP -sTCP:LISTEN -P | grep -E ':(2222|8080)'` shows no `0.0.0.0:*`.
- [ ] `ssh -p 2222 autoblog@localhost` auto-attaches to tmux with cwd `/agent`.
- [ ] `claude --version` inside the container succeeds (ANTHROPIC_API_KEY reached the shell).
- [ ] `curl http://localhost:8080` returns the placeholder HTML.
- [ ] SSH host keys persist across `docker compose down && up` (fingerprint unchanged).
- [ ] `.env` is gitignored; `.env.example` is committed.

## Files created in this phase

```
/Users/tbrownio/repos/autoblog/
├── README.md                     # quick-start + link to overview
├── .gitignore
├── .dockerignore
├── .env.example
├── compose.yml
├── Caddyfile
│
├── autoblog/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── bootstrap-volumes.sh
│   └── sshd_config
│
├── bin/
│   └── autoblog                  # laptop SSH wrapper
│
├── scripts/
│   └── install.sh
│
├── agent-template/               # seeded into /agent on first boot
│   ├── CLAUDE.md
│   └── .claude/
│       └── memory/
│           └── MEMORY.md         # empty index
│
└── static-template/              # Caddy placeholder (replaced by /site/prod/dist in 1b)
    └── index.html                # "hello from autoblog — Phase 1a"
```

Also:
- **DELETE** `docs/tailscale.md` — stale research note; architecture no longer uses Tailscale.

## Reference material

```yaml
- url: https://docs.linuxserver.io/images/docker-openssh-server/
  why: sshd-in-container pattern: persist /etc/ssh via volume, run `ssh-keygen -A` at entrypoint, PermitRootLogin prohibit-password, authorized_keys via env.

- url: https://docs.docker.com/reference/compose-file/services/#ports
  why: Explicit IP bind syntax — `"127.0.0.1:2222:22"` binds only to loopback. Omitting the IP binds to 0.0.0.0.

- url: https://code.claude.com/docs/en/authentication
  why: Claude Code precedence for API keys; ANTHROPIC_API_KEY env var works non-interactively.

- file: /Users/tbrownio/repos/autoblog/docs/autoblog-overview.md
  why: Architecture reference. This plan implements a subset of the overview.
```

## Known gotchas

```
# CRITICAL: Port binding syntax. `"2222:22"` binds to 0.0.0.0. Always use
# `"${SSH_BIND:-127.0.0.1}:2222:22"`. The default 127.0.0.1 is fail-safe.

# CRITICAL: sshd host keys — without a persistent volume on /etc/ssh/, every
# container restart regenerates keys and the user's known_hosts stops matching.

# CRITICAL: Claude Code in container needs ANTHROPIC_API_KEY available to the
# LOGGED-IN shell (not just container env). sshd does NOT pass the container env
# into login shells by default. Fix: PermitUserEnvironment yes + write
# /home/autoblog/.ssh/environment during bootstrap. This is read for BOTH
# interactive and non-interactive SSH, whereas .bashrc is interactive-only.

# CRITICAL: First-boot idempotency. bootstrap-volumes.sh runs every container
# start. It must check whether seeds have been applied (presence of
# /agent/CLAUDE.md) before copying.

# CRITICAL: tmux auto-attach on SSH login happens via .bashrc. Guard with an
# SSH_CONNECTION check so local docker exec shells don't recursively spawn tmux.
```

## Architecture for this phase

```
Host (laptop in 1a)
│
├─ autoblog container
│    ports: ${SSH_BIND:-127.0.0.1}:2222:22
│    volumes:
│      autoblog_agent  → /agent   (seeded from /opt/autoblog/templates/agent-template/)
│      autoblog_claude → /home/autoblog/.claude
│      autoblog_ssh    → /etc/ssh
│      autoblog_static → /srv/static  (seeded with placeholder HTML)
│    processes (entrypoint order):
│      1. bootstrap-volumes.sh (idempotent seed)
│      2. sshd -D (fg, keeps container alive)
│
└─ caddy container
     ports: ${CADDY_BIND:-127.0.0.1}:${CADDY_HTTP_PORT:-8080}:80
     mounts: autoblog_static:/srv/static:ro
     serves: /srv/static/
     depends_on: autoblog (healthy)
```

The `autoblog_static` volume is a temporary shim — it's seeded with the placeholder HTML by bootstrap and served by Caddy. In Phase 1b it is replaced by `autoblog_site` and the Caddy root is pointed at `/site/prod/dist/`.

## Implementation tasks

### Task 1 — Top-level repo files

**CREATE `.gitignore`:**
```
node_modules/
dist/
.env
.DS_Store
tmp/
.astro/
.claude/
```
(The `.claude/` entry hides Claude Code's project-side state on the user's laptop — it's irrelevant for server-side checkin.)

**CREATE `.dockerignore`:**
```
node_modules
.git
tmp/
.env
```

**CREATE `.env.example`:**
```bash
# --- required in all phases ---
ANTHROPIC_API_KEY=
SSH_PUBLIC_KEY="ssh-ed25519 AAAA... your-email@example.com"
TIMEZONE=America/Los_Angeles

# --- Phase 1 defaults (laptop sandbox). Leave as-is for local dev. ---
DOMAIN=localhost
SSH_BIND=127.0.0.1      # loopback only — reachable from the laptop itself
CADDY_BIND=127.0.0.1
CADDY_HTTP_PORT=8080
CADDY_HTTPS_PORT=8443

# --- Phase 2 overrides (see tmp/ready-plans/phase-2-vps.md) ---
# DOMAIN=your-real-domain.com
# SSH_BIND=0.0.0.0
# CADDY_BIND=0.0.0.0
# CADDY_HTTP_PORT=80
# CADDY_HTTPS_PORT=443
```

**CREATE `README.md`:**
- Tagline: "A personal agent-maintained knowledge base with a public website."
- Link to `idea.md` (concept) and `docs/autoblog-overview.md` (architecture).
- Quick start: clone, `cp .env.example .env`, edit API key + SSH key, `docker compose up -d --wait`.
- Link to the current phase plan under `tmp/ready-plans/`.

### Task 2 — compose.yml

**CREATE `compose.yml`:**

```yaml
services:
  autoblog:
    build: ./autoblog
    env_file: .env
    volumes:
      - autoblog_agent:/agent
      - autoblog_claude:/home/autoblog/.claude
      - autoblog_ssh:/etc/ssh
      - autoblog_static:/srv/static
    ports:
      - "${SSH_BIND:-127.0.0.1}:2222:22"
    healthcheck:
      test: ["CMD", "test", "-f", "/var/run/autoblog-ready"]
      interval: 5s
      timeout: 3s
      retries: 12
      start_period: 30s
    restart: unless-stopped

  caddy:
    image: caddy:2
    env_file: .env
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - autoblog_static:/srv/static:ro
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - "${CADDY_BIND:-127.0.0.1}:${CADDY_HTTP_PORT:-8080}:80"
      - "${CADDY_BIND:-127.0.0.1}:${CADDY_HTTPS_PORT:-8443}:443"
    depends_on:
      autoblog:
        condition: service_healthy
    restart: unless-stopped

volumes:
  autoblog_agent:
  autoblog_claude:
  autoblog_ssh:
  autoblog_static:
  caddy_data:
  caddy_config:
```

Healthcheck is tight in 1a (no Astro build yet). Phase 1b will relax `retries`/`start_period` to handle longer first-boot work.

### Task 3 — Caddyfile

**CREATE `Caddyfile`:**

```caddy
{$DOMAIN:localhost} {
    root * /srv/static
    file_server
    try_files {path} {path}/ /index.html
    encode gzip
    header / Cache-Control "public, max-age=60"
}
```

Phase 1 defaults serve over plain HTTP on container :80 (published to host :8080). Phase 2 sets `DOMAIN` to a real host; Caddy auto-obtains Let's Encrypt certs.

### Task 4 — autoblog Dockerfile

**CREATE `autoblog/Dockerfile`:**

```dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server tmux git curl ca-certificates sudo \
    python3 build-essential jq tini \
    && rm -rf /var/lib/apt/lists/*

# Node 20 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# User
RUN useradd --create-home --shell /bin/bash --uid 1000 autoblog \
    && usermod -aG sudo autoblog \
    && echo 'autoblog ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/autoblog

# tmux auto-attach on SSH login
RUN echo 'if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then exec tmux new-session -A -s main -c /agent; fi' \
    >> /home/autoblog/.bashrc \
    && chown autoblog:autoblog /home/autoblog/.bashrc

# sshd config + entrypoint scripts
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh bootstrap-volumes.sh /opt/autoblog/bin/
RUN chmod +x /opt/autoblog/bin/*.sh

# Templates (read at first boot; never mutated at runtime)
COPY templates/ /opt/autoblog/templates/

RUN mkdir -p /var/run/sshd /agent

EXPOSE 22
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/autoblog/bin/entrypoint.sh"]
```

Note: the `templates/` path in the build context is populated by the next task. In Phase 1a it only contains `agent-template/` and `static-template/`. Phase 1b adds `site-template/`; Phase 1c adds `vault-template/`.

### Task 5 — entrypoint + bootstrap

**CREATE `autoblog/entrypoint.sh`:**

```bash
#!/bin/bash
set -euo pipefail

echo "[autoblog] bootstrap starting…"
/opt/autoblog/bin/bootstrap-volumes.sh
echo "[autoblog] bootstrap complete; starting sshd."

exec /usr/sbin/sshd -D -e
```

**CREATE `autoblog/bootstrap-volumes.sh`:**

```bash
#!/bin/bash
set -euo pipefail

TEMPLATES=/opt/autoblog/templates

# Seed /agent on first boot
if [ ! -f /agent/CLAUDE.md ]; then
  echo "[bootstrap] seeding /agent"
  cp -r "$TEMPLATES/agent-template/." /agent/
  chown -R autoblog:autoblog /agent
fi

# Seed /srv/static on first boot (placeholder page for 1a; replaced in 1b)
if [ ! -f /srv/static/index.html ]; then
  echo "[bootstrap] seeding /srv/static"
  cp -r "$TEMPLATES/static-template/." /srv/static/
fi

# Generate SSH host keys if missing (idempotent — ssh-keygen -A won't overwrite)
ssh-keygen -A

# Inject authorized_keys from env (re-written every boot so env updates take effect)
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p /home/autoblog/.ssh
  echo "$SSH_PUBLIC_KEY" > /home/autoblog/.ssh/authorized_keys
  chmod 700 /home/autoblog/.ssh
  chmod 600 /home/autoblog/.ssh/authorized_keys
  chown -R autoblog:autoblog /home/autoblog/.ssh
fi

# Deliver ANTHROPIC_API_KEY to login shells via ~/.ssh/environment.
# sshd reads this when PermitUserEnvironment yes. Works for both interactive
# and non-interactive SSH; .bashrc does not.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  mkdir -p /home/autoblog/.ssh
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" > /home/autoblog/.ssh/environment
  chmod 600 /home/autoblog/.ssh/environment
  chown -R autoblog:autoblog /home/autoblog/.ssh
fi

# Readiness marker for the healthcheck
touch /var/run/autoblog-ready
echo "[bootstrap] ready"
```

### Task 6 — sshd_config

**CREATE `autoblog/sshd_config`:**

```
Port 22
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
AllowUsers autoblog
AuthorizedKeysFile /home/%u/.ssh/authorized_keys
PermitUserEnvironment yes        # required for ~/.ssh/environment (ANTHROPIC_API_KEY)
MaxAuthTries 3
LoginGraceTime 20
Subsystem sftp /usr/lib/openssh/sftp-server
```

### Task 7 — Agent template

**CREATE `agent-template/CLAUDE.md`:**

Describe the agent's role at the Phase 1a level:

- You are the autoblog agent, running inside a container on this host.
- Your working directory is `/agent`. Your skills live in `.claude/skills/`, your memory in `.claude/memory/`.
- Phase 1a: no site, no vault yet. Phases 1b/1c add those and accompanying skills.
- You reach the shell via `ssh -p 2222 autoblog@host`. `ANTHROPIC_API_KEY` is delivered to your shell via `~/.ssh/environment`.
- If the user asks for something you don't have a skill for, propose a new skill file and ask them to save it.

**CREATE `agent-template/.claude/memory/MEMORY.md`:**
```markdown
<!-- MEMORY.md is an index. Individual memory files live beside it and are referenced below. -->
```

No skills in 1a; 1b and 1c add them.

### Task 8 — Static placeholder

**CREATE `static-template/index.html`:**

Simple, readable HTML. Title "autoblog — Phase 1a." A paragraph explaining this is the placeholder served by Caddy; Phase 1b replaces it with the Astro production build.

### Task 9 — Laptop wrapper

**CREATE `bin/autoblog`:**

```bash
#!/bin/bash
set -euo pipefail

HOST="${AUTOBLOG_HOST:-localhost}"
PORT="${AUTOBLOG_PORT:-2222}"
USER="${AUTOBLOG_USER:-autoblog}"

TUNNEL_ARGS=()
if [ "${1:-}" = "--tunnel" ]; then
  TUNNEL_ARGS=(-L 4321:localhost:4321)
  shift
fi

exec ssh -p "$PORT" -t "${TUNNEL_ARGS[@]}" "$USER@$HOST" \
  "tmux new-session -A -s main -c /agent"
```

Header comment documents the Phase 1 / Phase 2 usage:
- Phase 1 (local Docker): defaults are correct; `--tunnel` has nothing to forward to yet (1b adds the dev server). Provided now for forward-compat.
- Phase 2 (VPS): set `AUTOBLOG_HOST=<vps-hostname>`, leave `AUTOBLOG_PORT=2222`, pass `--tunnel` once the dev server exists (1b+).

`chmod +x bin/autoblog`.

### Task 10 — Install script

**CREATE `scripts/install.sh`:**

```bash
#!/bin/bash
set -euo pipefail

command -v docker >/dev/null || { echo "ERROR: install Docker first."; exit 1; }
docker compose version >/dev/null || { echo "ERROR: install docker compose plugin."; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env created from .env.example — edit it to set ANTHROPIC_API_KEY and SSH_PUBLIC_KEY, then re-run this script."
  exit 0
fi

docker compose up -d --wait

echo
echo "autoblog is up."
echo "  SSH:  ssh -p 2222 autoblog@localhost"
echo "  Prod: http://localhost:8080  (placeholder in 1a; real site in 1b)"
```

### Task 11 — Delete deprecated file

`rm /Users/tbrownio/repos/autoblog/docs/tailscale.md` — architecture does not use Tailscale.

### Task 12 — Sanity check

Run:
```bash
docker compose config > /dev/null
docker compose build
docker compose up -d --wait
docker compose ps
```

## Validation loop

```bash
# 1. Compose resolves with default env
docker compose config > /dev/null

# 2. Build succeeds
docker compose build

# 3. Services come up healthy
docker compose up -d --wait
docker compose ps
# Expected: both healthy

# 4. Ports are loopback-only
lsof -iTCP -sTCP:LISTEN -P | grep -E ':(2222|8080)'
# Expected: every line includes 127.0.0.1:*; no 0.0.0.0:*

# 5. SSH drops into tmux at /agent
ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  autoblog@localhost "echo ok && pwd"
# Expected: "ok" and (for interactive SSH) cwd /agent

# 6. Claude CLI runs with inherited key
docker compose exec autoblog su - autoblog -c "claude --version"
# Expected: prints claude-code version

# 7. Caddy serves the placeholder
curl -sf http://localhost:8080 | head -5
# Expected: HTML containing "Phase 1a"

# 8. SSH host-key persistence
docker compose down && docker compose up -d --wait
ssh -p 2222 -o StrictHostKeyChecking=yes autoblog@localhost "echo ok"
# Expected: "ok" (no fingerprint-changed warning)

# 9. Agent files in place
docker compose exec autoblog ls /agent/.claude/memory/MEMORY.md
# Expected: file exists
```

## Final checklist

- [ ] `docker compose config` passes with the default `.env.example`.
- [ ] `docker compose build` completes.
- [ ] `docker compose up -d --wait` → both services healthy.
- [ ] Port bindings confirmed loopback-only.
- [ ] SSH works, drops into tmux at `/agent`.
- [ ] `claude --version` runs with `ANTHROPIC_API_KEY` inherited.
- [ ] `curl localhost:8080` returns the placeholder.
- [ ] Host keys persist across restart.
- [ ] `.env.example` committed; `.env` gitignored.
- [ ] `docs/tailscale.md` deleted.
- [ ] `README.md` points to `docs/autoblog-overview.md` and the current phase plan.

## Anti-patterns to avoid

- Writing port mappings without `${BIND_VAR:-127.0.0.1}:…`.
- Setting `PermitRootLogin yes` under any circumstance.
- Baking `ANTHROPIC_API_KEY` into the image.
- Delivering the API key via `.bashrc` (breaks for non-interactive SSH; use `.ssh/environment`).
- Starting supervisord — sshd as PID 1 is sufficient.
- Omitting `autoblog_ssh` volume — the container will re-key every restart.
- Adding Tailscale back as a "simplification." SSH meets the goal.

## Out of scope (in this phase)

- Astro site, two-worktree git, site deploy/rollback — **Phase 1b**.
- Vault, ingest skill, Obsidian Git setup — **Phase 1c**.
- VPS deployment (DNS, firewall, Let's Encrypt) — **Phase 2**.
- Backups, update mechanism, multi-user — not planned.

## Plan confidence

**9/10** for one-pass implementation. This phase is essentially "dockerize a hardened SSH box with Claude CLI and a Caddy static shim." All components are well-trodden. The likely correction surface is SSH env delivery (one tweak) or first-boot ordering (one tweak). No architectural risk.
