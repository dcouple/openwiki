# autoblog

A personal agent-maintained knowledge base with a public website.

- **Concept**: [idea.md](./idea.md)
- **Architecture**: [docs/autoblog-overview.md](./docs/autoblog-overview.md)
- **Current phase plan**: [tmp/ready-plans/phase-1a-container-scaffold.md](./tmp/ready-plans/phase-1a-container-scaffold.md)

## Quick start

```bash
git clone <this-repo>
cd autoblog
cp .env.example .env
# Edit .env: set ANTHROPIC_API_KEY and SSH_PUBLIC_KEY
docker compose up -d --wait
```

Once up:

```
ssh -p 2222 autoblog@localhost    # drops into tmux at /agent
http://localhost:8080             # placeholder page (Phase 1a); real site in Phase 1b
```

Or use the wrapper (after `chmod +x bin/autoblog` and adding `bin/` to your `PATH`):

```bash
autoblog
```
