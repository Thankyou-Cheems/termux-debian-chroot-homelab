# Public Export Notes

This repository is generated from a private `/opt/ops` control-plane repo.

Sanitization policy:

1. Runtime secrets are excluded (`secrets/live`).
2. Binary backup payloads are excluded (`backup-artifacts/latest`, `backup-artifacts/runs`).
3. Host-specific values are replaced with placeholders:
   - `<HOST_IP>`
   - `<TERMUX_USER>`
   - `<TERMUX_HOME>`
   - `<CHROOT_DIR>`
   - `<GITHUB_USER>`
   - `<DEPLOYMENT_REPO>`
   - `<NETWORK_SECRET>`
   - `<PEER_IP>`
4. Build fails if leak sentinel detects sensitive markers.

Regenerate:

1. `bash /opt/ops/scripts/export-public-repo.sh --force --output /opt/ops-public`
