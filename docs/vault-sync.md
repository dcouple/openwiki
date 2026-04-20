# Vault Sync — Obsidian Git Setup

## Overview

The vault is a git repo. The canonical copy is the bare repo at `/vault-remote.git` inside the autoblog container, reachable via SSH on port 2222.

Every device (laptop, desktop, phone) is an independent git clone. The Obsidian Git plugin handles pull/push automatically on a timer. The autoblog agent is also a git client — it works in `/vault/` (a clone inside the container), pulls before reading, and pushes after writing.

Write pattern: you touch `raw/` and only `raw/`; the agent touches everything else (`wiki/`, `log.md`, `index.md`). Real conflicts are rare because the two write domains rarely overlap.

## Laptop / desktop setup (macOS, Linux, Windows)

```bash
# 1. Make sure your SSH key is in .env as SSH_PUBLIC_KEY (same key used for the
#    agent shell works for git too).

# 2. Clone the vault onto your laptop:
git clone ssh://autoblog@localhost:2222/vault-remote.git ~/Documents/autoblog-vault

# (For Phase 2 on a VPS, replace `localhost` with your VPS hostname.)

# 3. Open the folder in Obsidian: File → Open Vault → select ~/Documents/autoblog-vault.

# 4. Install the Obsidian Git plugin:
#    Settings → Community plugins → Browse → search "Obsidian Git" → Install + Enable.

# 5. Configure Obsidian Git:
#    - Commit message on auto-backup: "vault: {{date}}" (or similar).
#    - Auto-backup interval: 5 minutes.
#    - Pull on start: ON.
#    - Pull on auto-backup: ON.
#    That's enough — the plugin will now commit your changes and pull the agent's
#    changes on a timer.
```

## Phone setup (iOS)

1. Install Obsidian Mobile from the App Store.
2. On the phone, generate an SSH key (via Blink Shell, Working Copy, or similar). Public key format: `ssh-ed25519 …`.
3. Add that public key to your `.env`'s `SSH_PUBLIC_KEY` (append it on a new line — each device gets its own key; `authorized_keys` supports multiple lines). Re-run `docker compose up -d` so bootstrap refreshes `authorized_keys` with the updated key set.
4. In Obsidian Mobile: Create a new vault in a local folder. Do NOT use iCloud sync.
5. Install the Obsidian Git plugin (same search flow as desktop).
6. Configure the git remote inside Obsidian Git's plugin settings: URL `ssh://autoblog@<host>:2222/vault-remote.git`. Point the plugin at your private key file stored in the app's sandboxed (private) storage.
7. Initial pull: the plugin runs pull-on-start; verify your vault content arrives.
8. Verify push: create `raw/test.md` in Obsidian Mobile, then wait for the auto-backup interval or trigger manually via the command palette (`Obsidian Git: Create backup and push`).

Note: iOS Obsidian Git setup is finickier than desktop. If you hit key-format or SSH config issues, the common fix is to re-export the private key in OpenSSH format (not PEM).

## Phone setup (Android)

Same flow as iOS. Key management is slightly easier — you can generate and store keys via Termux or the plugin's built-in key generator rather than a separate SSH client app.

## Multi-device key management

Each device has its own SSH key. `authorized_keys` inside the container supports one key per line:

```bash
# in .env
SSH_PUBLIC_KEY="ssh-ed25519 AAAA...laptop
ssh-ed25519 BBBB...desktop
ssh-ed25519 CCCC...phone"
```

The bootstrap script writes the `SSH_PUBLIC_KEY` env var directly to `authorized_keys`; newlines in the env var become newlines in the file. After editing `.env`, run `docker compose up -d` to apply.

## Conflict handling

Your write domain (`raw/`) and the agent's write domain (`wiki/`, `log.md`, `index.md`) are disjoint, so conflicts are rare in practice. When they do happen, Obsidian Git surfaces them as standard merge conflicts. To resolve:

1. Open the conflicted file. Git conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) will be visible.
2. Edit the file to keep the content you want, removing all conflict markers.
3. Commit and push.

If you're stuck and the conflict is in a wiki page (agent-authored territory) on a device where you have no edits worth keeping, the cleanest reset is:

```bash
# on the device with the problem
git fetch origin
git reset --hard origin/main
```

This discards local changes in favor of what's on the server. Only do this on a device where you haven't made edits you care about.

## What's NOT covered here

- **Obsidian Sync** (the paid service). It's end-to-end encrypted and doesn't let the container participate — so it doesn't work for this architecture. Use Obsidian Git instead.
- **Mutagen**. Has no mobile client and isn't used by this architecture.
