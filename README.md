<h1 align="center">openwiki</h1>

<p align="center"><strong>A personal wiki and public site that maintains itself — discoverable by people and by their agents.</strong></p>

<p align="center">
  <a href="#quickstart"><strong>Quickstart</strong></a> &middot;
  <a href="./docs/autoblog-overview.md"><strong>Architecture</strong></a> &middot;
  <a href="./docs/deploying-laptop.md"><strong>Laptop</strong></a> &middot;
  <a href="./docs/deploying-vps.md"><strong>VPS</strong></a> &middot;
  <a href="./docs/idea.md"><strong>Inspiration</strong></a>
</p>

<p align="center">
  <a href="#license"><img src="https://img.shields.io/badge/license-TBD-lightgrey" alt="License" /></a>
  <a href="https://github.com/dcouple/openwiki/stargazers"><img src="https://img.shields.io/github/stars/dcouple/openwiki?style=flat" alt="Stars" /></a>
  <a href="https://github.com/dcouple/openwiki/issues"><img src="https://img.shields.io/github/issues/dcouple/openwiki" alt="Issues" /></a>
</p>

<br/>

*Be discoverable — by people and by their agents. An open, self-hosted personal wiki and public site that maintains itself. Drop in notes, logs, and captures; the agent curates the wiki and keeps your site current.*

**If Obsidian is your private vault, openwiki is your published self.**

openwiki is a Docker-deployable personal wiki + public site. Drop sources into a folder, talk to a Claude Code agent over SSH, and watch your knowledge base and your site grow together — readable by you, by visitors, and by the agents that find you.

It extends [Andrej Karpathy's LLM Wiki pattern](./docs/idea.md) — entity pages, concept pages, and cross-references kept tidy by an agent that doesn't get bored — with an Astro site whose pages are written *intentionally* from vault content. Nothing leaks. Nothing rots.

**In the agent era, your public site is your new resume. openwiki keeps it alive.**

|        | Step                     | Example                                                                                      |
| ------ | ------------------------ | -------------------------------------------------------------------------------------------- |
| **01** | Connect your inputs      | Notes, voice memos, meeting transcripts, Cloud/Codex logs — anything goes into `vault/raw/`. |
| **02** | The agent curates        | Entities, concepts, and cross-references land in your private wiki. No effort required.     |
| **03** | Your site stays current  | The agent rebuilds your public site on a cron — or when you say *"ship it."*                 |

<br/>

> **COMING SOON: Friend graph + agent-to-agent messaging** — Send captures to your friends' agents, get a daily summary of what they're working on, and ask your own agent *"what would Parsa think?"* — answered from their public wiki. Public agent endpoints let visitors query your site directly.

<br/>

<div align="center">
<table>
  <tr>
    <td align="center"><strong>Built<br/>on</strong></td>
    <td align="center">🤖<br/><sub>Claude Code</sub></td>
    <td align="center">📓<br/><sub>Obsidian</sub></td>
    <td align="center">🚀<br/><sub>Astro</sub></td>
    <td align="center">🔒<br/><sub>Caddy</sub></td>
    <td align="center">🐳<br/><sub>Docker</sub></td>
    <td align="center">🌿<br/><sub>git</sub></td>
  </tr>
</table>

<em>One image, two phases. Whatever runs on your laptop is what runs on the VPS.</em>

</div>

<br/>

## openwiki is right for you if

- ✅ You want to be **findable by agents**, not just search engines
- ✅ You want **one site that evolves with your work**, not a LinkedIn you never update
- ✅ You like the idea of a **second brain** but every wiki you've started has rotted
- ✅ You want your site to be **the new resume** — alive, current, yours
- ✅ You'd rather **talk to an agent** than fight a CMS dashboard
- ✅ You want **the vault private and the site public** — with no surface for accidental leaks
- ✅ You want to **own the bytes**: your vault is a git repo on a box you control
- ✅ You want **one container** that runs the same on your laptop and your VPS

<br/>

## Features

<table>
<tr>
<td align="center" width="33%">
<h3>🧠 Agent-Maintained Wiki</h3>
The agent reads new sources, updates entity and concept pages, keeps the index honest, and logs every change.
</td>
<td align="center" width="33%">
<h3>📝 Intentional Publishing</h3>
Vault is private; site is public. Nothing crosses the line until you say so. <code>status: draft</code> vs <code>published</code> is the only lifecycle.
</td>
<td align="center" width="33%">
<h3>🛡️ Build-Gated Deploys</h3>
A successful <code>astro build</code> is required before any merge to <code>main</code>. Production cannot regress from a bad agent edit.
</td>
</tr>
<tr>
<td align="center">
<h3>📱 Multi-Device by Default</h3>
SSH + tmux from any device. Phone, laptop, desktop — every device is a git clone of the vault.
</td>
<td align="center">
<h3>🐳 One Image, Two Phases</h3>
Laptop and VPS run the same container. Phase 2 is an <code>.env</code> change, not an architecture change.
</td>
<td align="center">
<h3>🧩 Skills + Memory</h3>
Teach the agent something once. It remembers across sessions and devices. Ingest, publish, deploy, rollback — all just skills.
</td>
</tr>
<tr>
<td align="center">
<h3>🤖 Agent-Readable by Design</h3>
Your public wiki is structured for agents to crawl: entities, concepts, cross-references. Recruiters' copilots find you; friends' agents can ask you questions.
</td>
<td align="center">
<h3>↩️ One-Word Rollback</h3>
<em>"Roll back."</em> Non-destructive <code>git revert</code>, rebuild, redeploy.
</td>
<td align="center">
<h3>🔐 Auto-TLS in Production</h3>
Caddy fronts the public site with Let's Encrypt out of the box.
</td>
</tr>
</table>

<br/>

## Problems openwiki solves

| Without openwiki                                                                                                         | With openwiki                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| ❌ Recruiters google you and find a LinkedIn profile you last updated two years ago.                                     | ✅ They find a living wiki that shows how you actually think, kept current by an agent you never have to nag.                   |
| ❌ Your notes pile up but nothing connects. Links rot. Summaries go stale.                                               | ✅ The agent maintains entity and concept pages, keeps cross-references honest, and updates the index every ingest.            |
| ❌ Your private notes and your public site drift apart. What's on the site bears little resemblance to what you know.     | ✅ The site is composed from the wiki on every rebuild. They can't drift.                                                       |
| ❌ Hosted CMSes own your content and your URLs. Migration is painful and lossy.                                          | ✅ Your vault and site are git repos in a Docker volume on a box you control. Move it whenever you want.                       |
| ❌ Deploys are scary. A typo in a draft breaks the live site.                                                            | ✅ A successful build gates every merge to `main`. Bad edits never reach production. Rollback is one word.                     |
| ❌ Your private notes and your public site live in the same tool, so you self-censor or accidentally leak.               | ✅ Vault is private and never auto-published. Site is composed deliberately from vault content. Two repos, one agent.          |

<br/>

## Why openwiki is special

|                                   |                                                                                                              |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Agent owns the bookkeeping.**   | The agent runs ingest, indexing, cross-referencing, publishing, and deploys. You direct; it does the work.   |
| **Private vault, public site.**   | Two separate git repos. Nothing in the vault is ever rendered publicly without an explicit publish step.     |
| **Build is the gate.**            | `astro build` success in `dev/` is required before `dev → main` merges. Production cannot break from a typo. |
| **One image, two phases.**        | Whatever you prove on your laptop is what runs on the VPS. Phase 2 is an `.env` change, not a rewrite.       |
| **Multi-device, one tmux.**       | SSH from your phone, your laptop, or your desktop. Same session, same agent, same conversation.              |
| **Skills + memory persist.**      | Teach the agent something in one session; it knows it in the next. Stored in the agent's own root.           |
| **Git is invisible.**             | You think in deploys and rollbacks, not commits and merges. The agent owns git the same way it owns the site. |

<br/>

## What openwiki is not

|                              |                                                                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Not a hosted SaaS.**       | Self-hosted, your box, your bytes. We don't have an account system because there is no service.                          |
| **Not a Notion clone.**      | No drag-and-drop blocks. Markdown files, an Astro site, an Obsidian vault. Boring and durable.                           |
| **Not a multi-user CMS.**    | One person, one vault, one site. A friend graph is on the roadmap; multi-tenant editing is not.                          |
| **Not auto-publishing.**     | The agent never pushes a vault page to the site without you asking. Every public page is an intentional act.             |
| **Not a chat UI for visitors.** | Today, you talk to the agent over SSH. A public agent endpoint for site visitors is on the roadmap, not shipped.        |
| **Not RAG.**                 | `index.md` + grep + a reading agent is enough at the target scale. No vector store, no embeddings pipeline.              |

<br/>

## Quickstart

Self-hosted. Docker Compose. No account required.

On a fresh Debian 12 or Ubuntu 22.04+ VPS:

```bash
# On a fresh Debian/Ubuntu VPS:
curl -fsSL https://raw.githubusercontent.com/dcouple/openwiki/main/install.sh -o /tmp/openwiki-install.sh
sudo bash /tmp/openwiki-install.sh
```

The installer takes under two minutes. It installs Docker, configures `ufw` and `fail2ban`, pulls the latest image from GHCR, and prompts you for three things: a domain (optional), your SSH public key, and an Anthropic API key (optional — leave blank to use a Claude Pro/Max subscription). Then drop into the agent:

```bash
ssh -p 2222 -t autoblog@<vm-ip> "tmux new-session -A -s main -c /agent"
claude
```

Open `https://yourdomain.com` (or `http://<vm-ip>` if you skipped the domain) for the public site.

> **Requirements:** A VPS with `sudo` access, an SSH key, and either a Claude Pro/Max subscription or an Anthropic API key.

For the full first-run walkthroughs:
- [Run on a VPS (any provider)](./docs/deploying-vps.md) — **the canonical flow**
- [Run on a GCP VPS](./docs/deploying-gcp.md) — GCP-specific infra setup with daily snapshots
- [Run on a laptop (macOS)](./docs/deploying-laptop.md) — `git clone` + `docker compose` for hacking on openwiki itself; the installer is Linux-only
- [Multi-device vault sync](./docs/vault-sync.md)

<br/>

## Updating

On the VPS:

```bash
openwiki update --check   # is there a newer image?
openwiki update           # pull it and restart
```

Pulls the latest image from GHCR, atomically swaps in the new host config, and restarts the stack. Your vault, site, and agent data are untouched — they live in named Docker volumes. Optionally run `/sync-upstream` from inside the agent to pull new shipped skills.

See `openwiki help` for the full command list (`up`, `down`, `restart`, `status`, `logs`, `ssh`, `edit-env`, `set-domain`, `backup`, `update --check`, `version`).

<br/>

## How it works

Three roots, one agent, one container.

```
/vault   private knowledge base (Obsidian + git)
           raw/    you write here
           wiki/   agent writes here
           log.md  chronological record
           index.md catalog
/site    Astro project (dev + prod git worktrees)
/agent   Claude Code skills + memory
```

- **Vault** is private and never auto-published. You drop sources; the agent maintains the wiki.
- **Site** is an Astro project the agent edits on instruction. `dev` shows drafts; `main` is what the public sees.
- **Agent** is Claude Code with persistent skills and memory.

The vault lives in a bare git remote inside the container. Phone, laptop, desktop — every device is a clone, synced by Obsidian Git.

The full architecture lives in [`docs/autoblog-overview.md`](./docs/autoblog-overview.md).

<br/>

## FAQ

**Do I need to know Docker?**
You need it installed. The provided `compose.yml` does the rest.

**Do I need an Obsidian license?**
No — Obsidian is free for personal use. You can also edit the vault with any markdown editor.

**Can I use this without an Anthropic subscription?**
You need either a Claude Pro/Max subscription or an Anthropic API key for the agent. Pro/Max is usually cheaper for interactive use.

**Where does my content live?**
In Docker volumes on the host you deployed to. The vault and site are both git repos — back them up like any other repo.

**Is the vault really private?**
Yes. The vault has no rendered surface. The site is a separate Astro project the agent writes to deliberately, never automatically.

**Can other people read my site?**
Yes — that's the point. In Phase 2 (VPS) Caddy serves the public site at your domain over HTTPS via Let's Encrypt.

**What if the agent breaks production?**
It can't. Every deploy requires a successful `astro build` first. If the build fails, nothing ships. Rollback is `git revert`, non-destructive.

<br/>

## Roadmap

- ✅ Single-container Docker deploy
- ✅ Private Obsidian vault with bare git remote
- ✅ Astro site with draft/published lifecycle
- ✅ Build-gated deploys with one-word rollback
- ✅ SSH + tmux multi-device access
- ✅ Persistent skills and memory for the agent
- ✅ One image, two phases (laptop / VPS)
- ⚪ **Friend graph** — connect to other openwiki instances; send captures to friends' agents, get daily summaries of what they're working on
- ⚪ **Update notifications** — find out when people you follow publish
- ⚪ **Public agent endpoint** — let visitors ask your site questions
- ⚪ **Idea generation** — agent proposes timeline entries from your vault
- ⚪ Voice ingest — drop a voice memo, get a draft
- ⚪ Mobile-friendly agent UI
- ⚪ Pluggable site themes
- ⚪ One-click VPS provisioning

<br/>

## Principles

1. **The agent is the interface.** Don't memorize commands. Teach skills.
2. **Intentional publishing.** Nothing reaches the public by accident.
3. **The build is the gate.** A bad agent edit can't break production.
4. **Version control is invisible.** You think in deploys and rollbacks.
5. **One image, two phases.** Laptop and VPS run the same container.
6. **Small now, room later.** Boring choices first. Complexity earns its way in.

<br/>

## Credits

The wiki pattern is Andrej Karpathy's "LLM Wiki" note ([reproduced here](./docs/idea.md)). The deeper lineage is Vannevar Bush's 1945 *Memex*: a personal, curated knowledge store with trails between documents. openwiki is one instantiation, optimized for a single user with a private vault, a public site, and an agent in the middle.

<br/>

## License

TBD &copy; 2026 Dcouple, Inc.

<br/>

---

<p align="center">
  <sub>For people who want a website that's actually theirs — and who'd rather talk to an agent than wrestle a CMS.</sub>
</p>
