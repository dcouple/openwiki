# Tailscale

## What is Tailscale?

Tailscale is a mesh VPN built on [WireGuard](https://www.wireguard.com/). Once installed on a machine, that machine joins your private network — your *tailnet* — and can reach other machines on the same tailnet by a private IP (e.g. `100.64.1.2`) or a stable hostname (e.g. `autoblog-vps`). Nothing on that network is reachable from the public internet.

Think of it as "the same private network as my devices, everywhere I go" — no port forwarding, no firewall rules, no static IPs, no VPN server of your own to run.

## Networking basics (the parts that matter here)

**Public IPs vs private IPs.** When you rent a VPS, it gets a public IPv4 address (e.g. `34.72.x.x`). Anyone on the internet can try to connect to any open port on that address. That includes bots constantly scanning for open SSH, weak passwords, and unpatched services. This is not hypothetical — a fresh VPS with SSH open on port 22 sees authentication attempts within minutes of boot.

**Ports and firewalls.** A machine listens for connections on numbered ports (22 for SSH, 80 for HTTP, 443 for HTTPS). A firewall decides which ports the outside world can reach. Three common postures:

- *Open everything* — easy, unsafe.
- *Open only what's needed, harden what's exposed* — traditional: fail2ban, key-only SSH, maybe a non-standard port. Correct but fiddly; one misconfiguration is a breach.
- *Close the admin plane entirely; only serve what's genuinely meant to be public* — the posture we want.

**VPNs.** A VPN encrypts traffic between machines and makes them feel like they're on the same private network. Traditional VPNs (OpenVPN, hand-rolled WireGuard) require a server with a public IP, firewall rules, a key distribution story, and per-client config. Tailscale is WireGuard with all of that automated.

**NAT traversal.** Most networks (home wifi, cafes) sit behind a NAT — your laptop doesn't have a publicly routable address. Tailscale punches through NATs automatically using a technique called STUN, and falls back to relay servers (called DERP relays) when a direct connection isn't possible. You never configure this.

## The security problem we're solving

This project has two network surfaces:

1. **Public website** — anyone should be able to read the blog at `https://your-domain.com`. Caddy serves this on ports 80/443. This *has* to be reachable from the internet.
2. **Admin plane** — you SSH into the VPS to talk to the agent, edit files, and deploy. This *must not* be reachable from the internet. If an attacker can SSH in, they own the machine and everything the agent can touch.

The naive design exposes SSH on the VPS's public IP with a good key and hopes for the best. The Tailscale design puts SSH behind the tailnet: the public internet can't even send a packet to port 22. Not "tries and fails" — *can't reach it at all*.

## How we use Tailscale in this project

The compose stack has three services under the `prod` profile:

- **`tailscale`** — the sidecar. Joins the tailnet using a pre-auth key (`TS_AUTHKEY`) and provides the network stack for the other containers.
- **`autoblog`** — the main container (sshd, agent, Astro dev server). Uses `network_mode: service:tailscale`, which means it *shares the tailscale container's network namespace*. Any port it listens on (22, 4321) is reachable at the tailscale IP, not at the VPS's public IP.
- **`caddy`** — the public web server. Binds to the VPS's host ports 80/443 because the website *is* supposed to be public.

Net effect:

```
Public internet ──► VPS :80/:443 ──► caddy ──► /site/prod/dist/   (static site, HTTPS)
Your laptop ──(tailnet)──► autoblog-vps:22 ──► sshd ──► tmux ──► agent
```

Port 22 on the VPS's public IP is closed by the host firewall. You can't SSH from a coffee shop unless your laptop is on the same tailnet — which it will be, because you installed Tailscale on it once.

## Why a sidecar container, not `tailscale up` on the host

Two reasons:

1. **Portability.** The whole stack is a compose file. `docker compose up` on any Linux host gives an identical setup — no host-level Tailscale install to remember, no drift between VMs, no leftover state when you rebuild.
2. **Isolation.** The host's networking stays untouched. If you re-provision the VM, you redeploy the stack; nothing on the host needs to be rediscovered.

The trade-off: a container using `network_mode: service:tailscale` cannot declare its own `ports:` mapping, because the network namespace belongs to the tailscale container. That's why the implementation plan flags this as a critical gotcha — the dev profile (local laptop) skips the sidecar and uses direct port mapping instead.

## What you'll actually do

**One-time setup:**

1. Create a Tailscale account (free for personal use, up to 100 devices).
2. Install Tailscale on your laptop — `brew install tailscale` on macOS — and log in.
3. In the Tailscale admin console, generate a **pre-authentication key** (reusable if you plan to rebuild the VM; tagged is nice for ACLs). Put it in the VPS's `.env` as `TS_AUTHKEY=tskey-auth-...`.
4. On the VPS: `docker compose --profile prod up -d`. The sidecar uses the key to join the tailnet. The VPS appears in your Tailscale device list with a stable hostname.
5. In the admin console, enable **MagicDNS** so the VPS is reachable by name (e.g. `autoblog-vps`) instead of `100.x.x.x`.

**Daily use:**

- The `autoblog` wrapper script runs `ssh -t autoblog@<tailscale-hostname> "tmux new-session -A -s main -c /agent"`. No public DNS, no port forwarding, no key in an airport wifi login prompt.

**Revoking access:**

- Lost laptop? Remove it from the Tailscale admin console. It's immediately off the tailnet. SSH to the VPS is still closed to the rest of the internet, so no emergency key rotation is needed.

**Access controls (optional, later):**

- Tailscale ACLs let you restrict which devices in the tailnet can reach which ports on which other devices. For a single-user setup this is overkill, but if you ever add collaborators or a phone, ACLs are how you'd scope their access to (say) just the website and not SSH.

## Related files in this repo

- `compose.yml` — defines the `tailscale` service and the `network_mode: service:tailscale` wiring on autoblog
- `.env.example` — `TS_AUTHKEY` placeholder
- `docs/deploying.md` — the end-to-end VPS bring-up (auth key generation, first boot, DNS) once Phase 1 is built

## What Tailscale is *not*

- **Not a firewall replacement for the website** — the VPS's host firewall still needs to allow 80/443 for Caddy, and block 22. Tailscale doesn't manage that; it just makes SSH reachable over the tailnet instead.
- **Not a substitute for TLS** — the public site still uses HTTPS, because it serves the public internet. Tailscale only protects the admin plane.
- **Not a CDN or reverse proxy** — Caddy is that. Tailscale just decides which machines can see the SSH port.
