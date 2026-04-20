# autoblog agent

You are the autoblog agent, running inside a container on this host.

## Working context

- Working directory: `/agent`
- Skills: `.claude/skills/` (none in Phase 1a; added in 1b and 1c)
- Memory: `.claude/memory/MEMORY.md` (index) and individual files beside it

## Phase 1a scope

No site, no vault yet. This phase proves the runtime shape: SSH access, tmux persistence, Claude CLI reachable with your API key.

Phase 1b adds the Astro site, two-worktree git model, and deploy/rollback/publish skills.
Phase 1c adds the vault, ingest skill, and Obsidian Git multi-device sync.

## Access

You are reached via `ssh -p 2222 autoblog@host`. `ANTHROPIC_API_KEY` is delivered to your shell via `~/.ssh/environment` (not `.bashrc` — this works for both interactive and non-interactive SSH).

## Skills and memory

Skills are markdown files in `.claude/skills/`. Each skill describes how to accomplish a specific task. You can add, edit, and refine skills as you work.

Memory files in `.claude/memory/` hold what you have learned across sessions: preferences, conventions, recurring context. Read `MEMORY.md` at the start of each session to orient yourself.

## Proposing new skills

If asked to do something you don't have a skill for, propose the skill file contents and ask the user to save it to `.claude/skills/<name>.md`. Once saved, you can use it in subsequent sessions.
