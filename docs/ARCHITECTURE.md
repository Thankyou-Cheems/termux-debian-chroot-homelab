# Deployment Architecture (Minimal + Ops Git)

Last updated: `2026-02-25`

## 0) Read Context (Important)

1. This document path is `/opt/ARCHITECTURE.md`.
2. If you read it by local command (`cat /opt/ARCHITECTURE.md`), treat current shell as already inside Debian chroot.
3. Quick confirmation (no extra SSH): `test -f /etc/debian_version && echo in-debian`.

## 1) Layers

1. Host: Android + Termux (user `<TERMUX_USER>`)
2. Runtime: Debian chroot at `<CHROOT_DIR>` (root)
3. App CLI: Codex CLI in Debian
4. Business ops root: `/opt` (deployment + backup + restore)

## 2) Network Entry Points

1. Termux SSH: `<HOST_IP>:8022` (key-only, user `<TERMUX_USER>`)
2. Debian SSH: `<HOST_IP>:2222` (key-only, user `root`)
3. HomeAssistant UI: `<HOST_IP>:8123` (PM2 service, uv-managed, optional)
4. Syncthing UI (via Caddy): `<HOST_IP>:8080/syncthing/`

## 3) Startup & Script Nesting

```mermaid
flowchart TD
    A[Android Boot] --> B[Termux boot script: ~/.config/termux/boot/00-startup.sh]
    B --> C[Start/keep Termux sshd :8022]
    B --> D[su -c start-debian-root.sh '/usr/local/sbin/codex-start-sshd.sh']
    D --> E[Debian chroot mounted + entered]
    E --> F[/usr/local/sbin/codex-start-sshd.sh]
    F --> G[Start codex-fakeip-guard daemon]
    F --> I[Start/refresh PM2 business stack]
    F --> H[Debian sshd :2222]
    B --> H[termux-wake-lock]
```

Nested control points:
1. Outer orchestration: `~/.config/termux/boot/00-startup.sh`
2. Chroot entry wrapper: `~/.local/bin/start-debian-root.sh`
3. Persistent bind helper: `~/.local/bin/debian-persist-mounts-root.sh` (bind `Termux Home -> /mnt/termux-home` in chroot)
4. Inner daemon launcher: `/usr/local/sbin/codex-start-sshd.sh`
5. Fake-IP self-heal daemon: `/usr/local/sbin/codex-fakeip-guard.sh`
6. PM2 business bootstrap: `/opt/ops/scripts/pm2-start-business.sh` (called by `codex-start-sshd.sh`)

## 4) Runtime Control Scripts

1. Enter Debian: `~/.local/bin/start-debian`
2. Stop mounts: `~/.local/bin/stop-debian`
3. Start Debian sshd manually: `su -c "~/.local/bin/start-debian-root.sh '/usr/local/sbin/codex-start-sshd.sh'"`
4. Force one-shot fake-ip repair: `/usr/local/sbin/codex-fakeip-guard.sh once`
5. Restart fake-ip guard: `pkill -f "codex-fakeip-guard.sh daemon"; nohup /usr/local/sbin/codex-fakeip-guard.sh daemon >/tmp/codex-fakeip-guard.nohup 2>&1 &`
6. Ensure host mount inside Debian chroot: `~/.local/bin/debian-persist-mounts-root.sh ensure`
7. Release host mount inside Debian chroot: `~/.local/bin/debian-persist-mounts-root.sh release`
8. Manually reconcile PM2 business stack: `bash /opt/ops/scripts/pm2-start-business.sh`

## 5) Package & Tooling Management Strategy

1. Debian package source: TUNA mirror (`/etc/apt/sources.list`)
2. apt network policy (`/etc/apt/apt.conf.d/99codex-net`):
   - `APT::Sandbox::User "root";`
   - `Acquire::ForceIPv4 "true";`
3. Node toolchain policy:
   - `nodejs`/`npm` from Debian apt
   - `pnpm` via `corepack`
4. Codex install policy:
   - global install with `pnpm add -g @openai/codex`
   - real binary: `/root/.local/share/pnpm/codex`
   - stable entry wrapper: `/usr/local/bin/codex` (direct, no proxy injection)
5. Python app policy:
   - use `uv tool` for app-level Python runtime management
   - do not create project `venv` under `/opt`
   - HomeAssistant executable path: `/root/.local/bin/hass`
   - HomeAssistant is opt-in in `pm2-start-business.sh` (`ENABLE_HOMEASSISTANT=1`)
   - HomeAssistant is isolated by cgroup guard (`/sys/fs/cgroup/opt-homeassistant`) with memory high/max defaults

## 6) Update Policy (Minimal)

1. System packages: `apt-get update && apt-get upgrade -y`
2. Codex: `pnpm add -g @openai/codex@latest`
3. Validate: `codex --version`

## 7) Codex Fake-IP Stability Infra

1. Goal:
   - keep Codex usable when VPN uses fake-ip mapping (`198.18.0.0/15`) and stream reconnect appears.
2. Managed files:
   - guard script: `/usr/local/sbin/codex-fakeip-guard.sh`
   - startup integration: `/usr/local/sbin/codex-start-sshd.sh`
   - lock: `/run/codex-fakeip-guard.lock`
   - log: `/var/log/codex-fakeip-guard.log`
   - hosts managed block markers in `/etc/hosts`:
     - `# codex_no_fakeip_start`
     - `# codex_no_fakeip_end`
3. Mechanism:
   - daemon refreshes domain A records via DoH (`dns.google`, fallback `1.1.1.1/dns-query`)
   - writes real IP mappings to `/etc/hosts` managed block
   - default refresh interval: `15s`
   - single-instance protected by lock directory
4. Tunable env vars:
   - `CODEX_FAKEIP_DOMAINS` (default: `chatgpt.com`)
   - `REFRESH_INTERVAL_SEC` (default: `15`)

## 8) Rapid Verification

1. Confirm daemon:
   - `ps -eo pid,ppid,cmd | awk '/codex-fakeip-guard.sh daemon/ && !/awk/'`
2. Confirm no fake-ip for chatgpt:
   - `getent ahosts chatgpt.com | head -n 4`
3. Confirm Codex request path:
   - `codex exec --skip-git-repo-check --json -m gpt-5.2-codex 'Reply with OK only.'`
4. Inspect self-heal log:
   - `tail -n 50 /var/log/codex-fakeip-guard.log`

## 9) /opt Business Deployment Layout

Current layout:

```text
/opt
├── ARCHITECTURE.md
├── ops/                      # Git-managed control plane
│   ├── services/             # business source code (per service)
│   ├── scripts/              # deploy/backup/restore helpers
│   ├── deploy/cron/          # cron templates
│   ├── deploy/pm2/           # pm2 ecosystem configs
│   ├── env/                  # env templates only
│   ├── host/                 # Termux + Debian + Magisk(EasyTier) scripts (Git tracked)
│   ├── secrets/              # secrets mirror for private Git backup
│   └── docs/                 # runbooks
├── apps/                     # runtime releases (not in Git)
├── data/                     # persistent business data (not in Git)
├── logs/                     # runtime/ops logs (not in Git)
├── backup/
│   ├── git-bundles/          # offline code backups
│   └── data-snapshots/       # data snapshots
└── secrets/                  # runtime secrets canonical path
```

Separation rule:

1. `Code + automation` in `/opt/ops` (Git).
2. `Runtime artifacts` in `/opt/apps`.
3. `Stateful data` in `/opt/data`.
4. `Runtime secrets` in `/opt/secrets`.
5. `Git-tracked secret mirror` in `/opt/ops/secrets/live` (private repo only).
6. Runtime log directories under `/opt/apps/*/current/logs` are symlinked to `/opt/logs/*`.

## 10) Git Strategy For Recoverability

1. Canonical repo path: `/opt/ops`.
2. Production branch: `main`.
3. Release rollback point: Git tag `prod-YYYYMMDD-HHMM`.
4. Local offline backup: `git bundle` to `/opt/backup/git-bundles`.
5. Optional remote mirror: add a normal Git remote (`origin`) and push `main + tags`.

Minimal policy (private mirror mode):

1. Commit only templates for normal environment files (`env/*.example`).
2. Real credentials are stored in `/opt/secrets`, and mirrored to `/opt/ops/secrets/live` for private backup.
3. `origin` must stay private when mirroring secrets in Git.
4. Keep deployed state out of repo (`/opt/apps`, `/opt/data`, `/opt/logs`).

## 11) Deployment Flow (Implemented)

Implemented scripts:

1. `/opt/ops/scripts/deploy.sh`
2. `/opt/ops/scripts/backup.sh`
3. `/opt/ops/scripts/restore.sh`
4. `/opt/ops/scripts/install-cron.sh`
5. `/opt/ops/scripts/lib.sh`
6. `/opt/ops/scripts/prune-backup-history.sh`

Deploy a service from Git ref:

```bash
bash /opt/ops/scripts/deploy.sh --service <service_name> --ref main
```

Deployment result:

1. New release directory: `/opt/apps/<service_name>/releases/<timestamp>/`
2. Stable link updated: `/opt/apps/<service_name>/current -> .../releases/<timestamp>/`
3. Deployment metadata in release dir:
   - `.deploy_ref`
   - `.deploy_commit`
   - `.deploy_time_utc`

Rollback:

```bash
bash /opt/ops/scripts/deploy.sh --service <service_name> --ref prod-YYYYMMDD-HHMM
```

## 12) Backup And Restore Flow (Implemented)

Manual backup:

```bash
bash /opt/ops/scripts/backup.sh
```

Outputs:

1. Code bundle: `/opt/backup/git-bundles/ops-<timestamp>.bundle`
2. Data snapshot: `/opt/backup/data-snapshots/data-<timestamp>.tar.gz` (contains `/opt/data`, with secret symlinks only, excludes `/opt/data/syncthing/sync`)
3. Repo backup artifacts mirror: `/opt/ops/backup-artifacts/runs/<timestamp>/*` and `/opt/ops/backup-artifacts/latest/*` (symlink pointers)
4. Repo large artifacts retention: keep latest 3 runs by default (`--repo-artifacts-keep` to override)
5. Old `backup-artifacts/runs/*` paths are pruned from Git history automatically (filter-repo-like rewrite, requires clean tracked worktree)
6. Secrets mirror is backed up via Git commit content under `/opt/ops/secrets/live`
7. Manual backup run creates a dedicated commit for `backup-artifacts + secrets/live`
8. Temp directories under `/opt/backup/data-snapshots/` are pruned by default when older than retention days.
9. `uv tool` binary/runtime cache (for HomeAssistant) is not part of `/opt` backup; rebuild via `/opt/ops/scripts/uv-install-homeassistant.sh`.

Restore from bundle and data snapshot:

```bash
bash /opt/ops/scripts/restore.sh \
  --bundle /opt/backup/git-bundles/ops-<timestamp>.bundle \
  --data /opt/backup/data-snapshots/data-<timestamp>.tar.gz \
  --ref main \
  --force-data
```

Restore behavior:

1. If `/opt/ops` is not a repo, clone from bundle.
2. If `/opt/ops` is already a repo, fetch refs from bundle.
3. If restoring data with `--force-data`, old `/opt/data` is moved to `/opt/data.pre-restore-<timestamp>`.

## 13) Scheduled Backup (Optional)

Cron template path:

1. `/opt/ops/deploy/cron/ops-backup.cron`

Install cron service and schedule:

```bash
apt-get update && apt-get install -y cron
bash /opt/ops/scripts/install-cron.sh
```

Default schedule:

1. Daily at `03:17`, run:
   - `/opt/ops/scripts/backup.sh --retention-days 14`
2. Log file:
   - `/opt/logs/ops-backup.log`

## 14) Ops Verification Checklist

1. Confirm `/opt` structure:
   - `find /opt -maxdepth 2 -type d | sort`
2. Confirm ops repo:
   - `git -C /opt/ops status --short --branch`
3. Confirm deploy helper works:
   - `bash /opt/ops/scripts/deploy.sh --help`
4. Confirm backup helper works:
   - `bash /opt/ops/scripts/backup.sh --help`
5. Confirm restore helper works:
   - `bash /opt/ops/scripts/restore.sh --help`
6. Confirm PM2 helpers are executable:
   - `test -x /opt/ops/scripts/pm2-start-business.sh`
   - `test -x /opt/ops/scripts/pm2-check-business.sh`

## 15) Legacy Import Policy (Modern-Only)

1. Active runtime paths:
   - `/opt/apps/*`
   - `/opt/data/*`
2. Hard rules:
   - do not restore `termux/*`
   - do not recreate legacy aliases (`/opt/ASF`, `/opt/mcsmanager`, `/opt/update.sh`, etc.)
   - runtime and data must stay under `/opt/apps` + `/opt/data`

## 16) PM2 Business Runtime

1. PM2 ecosystem file:
   - `/opt/ops/deploy/pm2/ecosystem.business.config.js`
2. Start/update stack:
   - `bash /opt/ops/scripts/pm2-start-business.sh`
3. Health check:
   - `bash /opt/ops/scripts/pm2-check-business.sh`
4. Managed processes:
   - `asf`
   - `mcs-daemon`
   - `mcs-web`
   - `aria2`
   - `syncthing`
   - `caddy`
   - `syncthing` process user: `syncthing` (non-root)
5. Caddy route map (`:8080`):
   - `/` -> Fluent gateway page
   - `/mcs/` -> MCSManager panel
   - `/asf/` -> ASF web
   - `/aria2/` -> AriaNg
   - `/syncthing/` -> Syncthing GUI (proxied to `127.0.0.1:8384`)
   - `/jsonrpc` and `/ws` -> Aria2 RPC
6. Gateway static page source:
   - `/opt/ops/services/portal/index.html` (Git tracked)
7. Caddy config single source of truth:
   - `/opt/data/caddy/Caddyfile`
   - `/opt/data/caddy/upstreams.env`
8. Compatibility links (must stay symlink):
   - `/opt/apps/caddy/current/Caddyfile -> /opt/data/caddy/Caddyfile`
   - `/opt/apps/caddy/current/upstreams.env -> /opt/data/caddy/upstreams.env`
9. `pm2-start-business.sh` behavior:
   - repairs the compatibility symlinks automatically
   - syncs `ASF_UPSTREAM` from `/opt/data/asf/config/IPC.config` when available
   - ensures `SYNCTHING_UPSTREAM` default (`127.0.0.1:8384`) when missing

## 17) Host Script Git Tracking

1. Tracked path in repo:
   - `/opt/ops/host/termux/boot`
   - `/opt/ops/host/termux/bin`
   - `/opt/ops/host/debian/sbin`
2. Import runtime scripts into repo:
   - `bash /opt/ops/scripts/import-host-scripts.sh`
   - example with mounted Termux home: `bash /opt/ops/scripts/import-host-scripts.sh --termux-home /mnt/termux-home`
3. Install tracked scripts back to runtime paths:
   - `bash /opt/ops/scripts/install-host-scripts.sh`
   - example with mounted Termux home: `bash /opt/ops/scripts/install-host-scripts.sh --termux-home /mnt/termux-home`
4. Current Termux helpers in scope:
   - `00-startup.sh`
   - `start-debian`
   - `start-debian-root.sh`
   - `stop-debian`
   - `stop-debian-root.sh`
   - `debian-persist-mounts-root.sh`
5. Persistent mount policy:
   - `start-debian-root.sh` ensures `TERMUX_HOME -> <CHROOT_DIR>/mnt/termux-home`
   - `stop-debian-root.sh` releases that mount before unmounting other chroot mounts

## 18) Secrets Runtime + Git Mirror

1. Runtime canonical path:
   - `/opt/secrets`
2. Git-tracked mirror path:
   - `/opt/ops/secrets/live`
3. Migration helper:
   - `bash /opt/ops/scripts/migrate-secrets-to-runtime.sh`
4. Sync helpers:
   - export runtime -> repo: `bash /opt/ops/scripts/sync-secrets-repo.sh export`
   - import repo -> runtime: `bash /opt/ops/scripts/sync-secrets-repo.sh import`
5. Service compatibility:
   - sensitive files remain reachable via original `/opt/data/...` paths through symlinks
6. Remote requirement:
   - only push this repo to private remotes when `secrets/live` is tracked
