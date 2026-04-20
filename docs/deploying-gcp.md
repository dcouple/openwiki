# Deploying autoblog on Google Cloud Platform

Minimum-steps guide for running autoblog on a GCE VM with a separate, snapshotted data disk. For generic VPS deployment and post-deploy verification, see `docs/deploying.md`.

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- A domain you control
- Phase 1 of autoblog validated locally

## Variables

Set once per shell session. These are referenced by every command below.

```bash
export PROJECT_ID=your-project
export REGION=us-central1
export ZONE=us-central1-a
export DOMAIN=autoblog.example.com
export INSTANCE=autoblog-vm
export DATA_DISK=autoblog-data
gcloud config set project $PROJECT_ID
```

## 1. Reserve a static IP

```bash
gcloud compute addresses create autoblog-ip --region=$REGION
gcloud compute addresses describe autoblog-ip --region=$REGION --format='value(address)'
```

Save the returned IP.

## 2. Point DNS at the static IP

At your registrar, create an A record: `$DOMAIN` → the IP from step 1. Verify from a neutral location before proceeding:

```bash
dig +short $DOMAIN
```

Do not continue until this returns the static IP. Caddy's first-boot Let's Encrypt request will fail and rate-limit the domain if DNS isn't ready.

## 3. Create the data disk

A separate persistent disk holds all Docker state (images + volumes: vault, site, Caddy certs). Keeping it off the boot disk means the VM is disposable and only the data disk needs backing up.

```bash
gcloud compute disks create $DATA_DISK \
  --size=20GB \
  --type=pd-balanced \
  --zone=$ZONE
```

## 4. Attach a daily snapshot schedule (backups)

```bash
gcloud compute resource-policies create snapshot-schedule autoblog-daily \
  --region=$REGION \
  --max-retention-days=14 \
  --start-time=08:00 \
  --daily-schedule \
  --on-source-disk-delete=keep-auto-snapshots

gcloud compute disks add-resource-policies $DATA_DISK \
  --resource-policies=autoblog-daily \
  --zone=$ZONE
```

Daily snapshots, 14-day retention, preserved even if the disk is deleted.

## 5. Firewall rules

Scoped by network tag so they apply only to this VM. Port 22 (host sshd) is already open via the default network's `default-allow-ssh` rule.

```bash
gcloud compute firewall-rules create autoblog-web \
  --allow=tcp:80,tcp:443 \
  --target-tags=autoblog \
  --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create autoblog-ssh-container \
  --allow=tcp:2222 \
  --target-tags=autoblog \
  --source-ranges=0.0.0.0/0
```

## 6. Create the VM

```bash
gcloud compute instances create $INSTANCE \
  --zone=$ZONE \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --disk=name=$DATA_DISK,device-name=autoblog-data,mode=rw,boot=no \
  --address=$(gcloud compute addresses describe autoblog-ip --region=$REGION --format='value(address)') \
  --tags=autoblog
```

## 7. Prepare the disk and install Docker

```bash
gcloud compute ssh $INSTANCE --zone=$ZONE
```

Inside the VM:

```bash
# Format + mount the data disk (first-time setup only)
sudo mkfs.ext4 -F -m 0 /dev/disk/by-id/google-autoblog-data
sudo mkdir -p /mnt/disks/autoblog-data
sudo mount /dev/disk/by-id/google-autoblog-data /mnt/disks/autoblog-data
echo '/dev/disk/by-id/google-autoblog-data /mnt/disks/autoblog-data ext4 discard,defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker

# Point Docker's data-root at the mounted disk BEFORE first use
sudo mkdir -p /mnt/disks/autoblog-data/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "data-root": "/mnt/disks/autoblog-data/docker" }
EOF
sudo systemctl restart docker
docker info | grep "Docker Root Dir"
# Expected: Docker Root Dir: /mnt/disks/autoblog-data/docker
```

## 8. Clone repo and configure `.env`

```bash
sudo mkdir -p /opt && sudo chown $USER /opt
git clone https://github.com/<you>/autoblog /opt/autoblog
cd /opt/autoblog
cp .env.example .env
$EDITOR .env
```

Required `.env` values for GCP:

```
DOMAIN=your-domain.com
SSH_BIND=0.0.0.0
DEV_BIND=127.0.0.1
CADDY_BIND=0.0.0.0
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
ANTHROPIC_API_KEY=sk-ant-...
SSH_PUBLIC_KEY="ssh-ed25519 AAAA...your-laptop-key"
```

`DEV_BIND=127.0.0.1` is mandatory — the dev server is reached via `ssh -L` tunnel from your laptop, never publicly exposed.

## 9. First deploy

```bash
docker compose up -d --wait
docker compose logs -f caddy
```

Watch for `certificate obtained successfully`. First boot takes 3–10 minutes (npm install + initial Astro build).

## 10. Verify

From your laptop:

```bash
curl -sI https://$DOMAIN | head -3       # HTTP/2 200, Let's Encrypt cert
ssh -p 2222 autoblog@$DOMAIN "echo ok"   # "ok"
```

Full verification (listen bindings, vault git clone, dev tunnel) is in `docs/deploying.md`.

## Restoring from a snapshot

If the VM or data disk is lost:

```bash
# Find the most recent snapshot
gcloud compute snapshots list --filter="sourceDisk~autoblog-data"

# Recreate the disk from it
gcloud compute disks create $DATA_DISK \
  --source-snapshot=<snapshot-name> \
  --zone=$ZONE

# Re-run steps 6 and 7 (the fstab line auto-mounts on boot;
# Docker's data-root config puts you back on the same volumes).
docker compose up -d --wait
```

## Out of scope

- IAM hardening beyond the default Compute Engine service account
- VPC isolation (the default network is used)
- Cloud DNS (A record is managed at your registrar)
- Cloud Monitoring / alerting
- fail2ban, ufw, and other host hardening (see `docs/deploying.md`)
