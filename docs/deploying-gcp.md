# Deploying openwiki on Google Cloud Platform

Minimum-steps guide for running openwiki on a GCE VM with a separate, snapshotted data disk. Once the VM and data disk are up, the app install itself is the one-liner from [`deploying-vps.md`](./deploying-vps.md).

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- A domain you control
- Local laptop validated per [`deploying-laptop.md`](./deploying-laptop.md) (optional, but recommended before production)

## Variables

Set once per shell session. These are referenced by every command below.

```bash
export PROJECT_ID=your-project
export REGION=us-central1
export ZONE=us-central1-a
export DOMAIN=openwiki.example.com
export INSTANCE=openwiki-vm
export DATA_DISK=openwiki-data
gcloud config set project $PROJECT_ID
```

## 1. Reserve a static IP

```bash
gcloud compute addresses create openwiki-ip --region=$REGION
gcloud compute addresses describe openwiki-ip --region=$REGION --format='value(address)'
```

Save the returned IP.

## 2. Point DNS at the static IP

At your registrar, create an A record: `$DOMAIN` → the IP from step 1. Verify from a neutral location before proceeding:

```bash
dig +short $DOMAIN
```

Do not continue until this returns the static IP. Caddy's first-boot Let's Encrypt request will fail and rate-limit the domain if DNS isn't ready. The openwiki installer's DNS precheck catches this too, but it's cheaper to fix it here.

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
gcloud compute resource-policies create snapshot-schedule openwiki-daily \
  --region=$REGION \
  --max-retention-days=14 \
  --start-time=08:00 \
  --daily-schedule \
  --on-source-disk-delete=keep-auto-snapshots

gcloud compute disks add-resource-policies $DATA_DISK \
  --resource-policies=openwiki-daily \
  --zone=$ZONE
```

Daily snapshots, 14-day retention, preserved even if the disk is deleted.

## 5. Firewall rules

Scoped by network tag so they apply only to this VM. Port 22 (host sshd) is already open via the default network's `default-allow-ssh` rule. The openwiki installer also sets up `ufw` inside the VM, but GCP firewall rules are enforced at the network layer so they need to be configured here too.

```bash
gcloud compute firewall-rules create openwiki-web \
  --allow=tcp:80,tcp:443 \
  --target-tags=openwiki \
  --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create openwiki-ssh-container \
  --allow=tcp:2222 \
  --target-tags=openwiki \
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
  --disk=name=$DATA_DISK,device-name=openwiki-data,mode=rw,boot=no \
  --address=$(gcloud compute addresses describe openwiki-ip --region=$REGION --format='value(address)') \
  --tags=openwiki
```

## 7. Prepare the disk and point Docker at it

```bash
gcloud compute ssh $INSTANCE --zone=$ZONE
```

Inside the VM, **before installing openwiki**:

```bash
# Format + mount the data disk (first-time setup only)
sudo mkfs.ext4 -F -m 0 /dev/disk/by-id/google-openwiki-data
sudo mkdir -p /mnt/disks/openwiki-data
sudo mount /dev/disk/by-id/google-openwiki-data /mnt/disks/openwiki-data
echo '/dev/disk/by-id/google-openwiki-data /mnt/disks/openwiki-data ext4 discard,defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Install Docker first, so we can point its data-root at the data disk
# BEFORE any image pulls or volume creates happen in step 8.
curl -fsSL https://get.docker.com | sudo sh

# Point Docker's data-root at the mounted disk BEFORE first use
sudo mkdir -p /mnt/disks/openwiki-data/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "data-root": "/mnt/disks/openwiki-data/docker" }
EOF
sudo systemctl restart docker
docker info | grep "Docker Root Dir"
# Expected: Docker Root Dir: /mnt/disks/openwiki-data/docker
```

This step is the reason GCP needs its own guide: we need Docker configured to write to the data disk **before** the openwiki installer's `docker pull` runs, otherwise volumes land on the boot disk and the snapshot schedule doesn't cover them.

## 8. Install openwiki

Follow [`deploying-vps.md`](./deploying-vps.md) starting at **Section 2 (Install)**. The installer will detect that Docker is already present and skip reinstalling it.

In short:

```bash
curl -fsSL https://raw.githubusercontent.com/dcouple/openwiki/main/install.sh -o /tmp/openwiki-install.sh
sudo bash /tmp/openwiki-install.sh
```

At the domain prompt, enter `$DOMAIN` (the value you set at the top of this guide). The installer's DNS precheck will confirm the A record resolves to the VM's public IP before it starts Caddy.

## 9. Verify

From your laptop:

```bash
curl -sI https://$DOMAIN | head -3       # HTTP/2 200, Let's Encrypt cert
ssh -p 2222 autoblog@$DOMAIN "echo ok"   # "ok"
```

Full verification and daily operations (`openwiki status`, `openwiki update`, `openwiki backup`, etc.) are documented in [`deploying-vps.md`](./deploying-vps.md).

## Restoring from a snapshot

If the VM or data disk is lost:

```bash
# Find the most recent snapshot
gcloud compute snapshots list --filter="sourceDisk~openwiki-data"

# Recreate the disk from it
gcloud compute disks create $DATA_DISK \
  --source-snapshot=<snapshot-name> \
  --zone=$ZONE

# Re-run steps 6 and 7 (the fstab line auto-mounts on boot;
# Docker's data-root config puts you back on the same volumes).
# Then in step 8 the installer detects the existing /opt/openwiki layout
# (from the restored disk, if you kept it there) or just re-installs and
# re-attaches to the same named volumes.
docker compose -f /opt/openwiki/compose.yml up -d --wait
```

## Out of scope

- IAM hardening beyond the default Compute Engine service account
- VPC isolation (the default network is used)
- Cloud DNS (A record is managed at your registrar)
- Cloud Monitoring / alerting
- Host-level hardening beyond what the installer does (`ufw`, `fail2ban` are handled; see [`deploying-vps.md`](./deploying-vps.md))
