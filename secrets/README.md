# Secrets In Git (Private Repo Only)

This directory stores a Git-tracked mirror of runtime secrets for private backup.

Paths:

1. Runtime canonical path: `/opt/secrets`
2. Git-tracked mirror path: `/opt/ops/secrets/live`

Sync commands:

1. Export runtime to repo mirror:
   - `bash /opt/ops/scripts/sync-secrets-repo.sh export`
2. Import repo mirror to runtime:
   - `bash /opt/ops/scripts/sync-secrets-repo.sh import`

Migration command:

1. Move credentials out of `/opt/data` and wire symlinks:
   - `bash /opt/ops/scripts/migrate-secrets-to-runtime.sh`

Security note:

1. This content is sensitive even in private repositories.
2. Keep repository access strictly controlled and enable 2FA on GitHub.
