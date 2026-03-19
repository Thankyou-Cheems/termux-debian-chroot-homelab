# Termux Debian Chroot Homelab

This repository is a deployable blueprint for running a small self-hosted stack on an Android phone with:

1. Termux on the host
2. A Debian chroot as the main runtime
3. PM2-managed services under `/opt`
4. Caddy as the unified web entrypoint

It is a public, sanitized repo. Real secrets, host-specific addresses, and private runtime payloads are removed or replaced with placeholders.

## What You Get

The reference stack currently includes:

1. Caddy on `:8080`
2. MCSManager
3. ArchiSteamFarm
4. aria2 + AriaNg
5. Transmission + tracker refresh
6. Syncthing
7. File Browser
8. Tinyproxy
9. Optional Home Assistant

Typical web entrypoints are exposed behind one gateway, for example:

1. `/mcs/`
2. `/asf/`
3. `/aria2/`
4. `/syncthing/`
5. `/files/`

## Layout

The deployment is intentionally split into layers:

1. Host OS: Android + Termux
2. Runtime OS: Debian chroot
3. Git control plane: `/opt/ops`
4. Runtime apps: `/opt/apps`
5. Stateful data: `/opt/data`
6. Logs: `/opt/logs`

That separation keeps the stack maintainable:

1. Git tracks scripts, templates, docs, and portal assets
2. Runtime services stay replaceable
3. Data can be backed up separately from code
4. Large download directories can be excluded from routine snapshots

## Deploy SOP

Use this order on a fresh device:

1. Prepare Termux and the Debian chroot
2. Clone this repo into `/opt/ops`
3. Import the host-side scripts into the tracked repo view
4. Install the host-side scripts back to their runtime locations
5. Install the runtime packages required by the stack
6. Start the PM2 business stack
7. Run the health checks

Core commands:

```bash
bash /opt/ops/scripts/import-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk
bash /opt/ops/scripts/install-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk
bash /opt/ops/scripts/pm2-start-business.sh
bash /opt/ops/scripts/pm2-check-business.sh
```

If you also run Home Assistant:

```bash
bash /opt/ops/scripts/uv-install-homeassistant.sh
ENABLE_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-start-business.sh
CHECK_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-check-business.sh
```

## Daily Operations

Most routine tasks already have entrypoint scripts:

1. Start or reconcile services:
   `bash /opt/ops/scripts/pm2-start-business.sh`
2. Run health checks:
   `bash /opt/ops/scripts/pm2-check-business.sh`
3. Create a backup:
   `bash /opt/ops/scripts/backup.sh`
4. Restore from a Git bundle and data snapshot:
   `bash /opt/ops/scripts/restore.sh --bundle <bundle> --data <snapshot> --force-data`
5. Publish the sanitized public mirror:
   `bash /opt/ops/scripts/publish-public-repo.sh`

## Backup Model

The backup flow is designed for mobile storage constraints.

By default:

1. Git control-plane state is bundled
2. `/opt/data` is snapshotted
3. Large or reproducible payloads are excluded from the data snapshot

Default exclusions include:

1. `/opt/data/syncthing/sync`
2. `/opt/data/aria2/data`
3. `/opt/data/transmission/data`
4. `/opt/data/transmission/incomplete`
5. `/opt/data/filebrowser/root`

This keeps routine backups focused on recoverable configuration and operational state, instead of redownloading huge media or image files.

## What This Public Repo Is For

This repo is best treated as:

1. A deployment reference
2. A reusable script and template library
3. A blueprint for your own Android homelab stack

It is not a plug-and-play image, and it is not a dump of a live private environment.

You should expect to customize:

1. Network addresses
2. Proxy configuration
3. EasyTier peer details
4. Secrets and credentials
5. Service-specific runtime choices

## Repo Map

Important paths:

1. `scripts/`: operational entrypoints
2. `deploy/`: PM2, Caddy, and cron templates
3. `docs/`: architecture and runbooks
4. `host/`: Termux, Debian, and Magisk-side scripts
5. `services/portal/`: unified entry portal

## Read Next

If you are deploying from scratch, read these in order:

1. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
2. [host/README.md](host/README.md)
3. [docs/OPERATIONS.md](docs/OPERATIONS.md)
4. [docs/DOWNLOAD_STACK.md](docs/DOWNLOAD_STACK.md)
5. [docs/PUBLIC_REPO.md](docs/PUBLIC_REPO.md)
