#!/system/bin/sh
set -eu

CHROOT_DIR="${CHROOT_DIR:-<CHROOT_DIR>}"
TERMUX_HOME="${TERMUX_HOME:-<TERMUX_HOME>}"
MOUNT_POINT="${MOUNT_POINT:-$CHROOT_DIR/mnt/termux-home}"

is_mounted() {
  awk -v m="$1" '$2==m { found=1 } END { exit !found }' /proc/mounts
}

ensure_mount() {
  if [ ! -d "$TERMUX_HOME" ]; then
    echo "skip missing TERMUX_HOME: $TERMUX_HOME" >&2
    return 0
  fi
  mkdir -p "$MOUNT_POINT"
  if ! is_mounted "$MOUNT_POINT"; then
    mount --bind "$TERMUX_HOME" "$MOUNT_POINT"
  fi
}

release_mount() {
  while is_mounted "$MOUNT_POINT"; do
    umount -lf "$MOUNT_POINT" 2>/dev/null || break
  done
}

case "${1:-ensure}" in
  ensure)
    ensure_mount
    ;;
  release|umount|unmount)
    release_mount
    ;;
  *)
    echo "usage: $0 [ensure|release]" >&2
    exit 1
    ;;
esac
