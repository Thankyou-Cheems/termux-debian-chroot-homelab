#!/system/bin/sh
set -eu
CHROOT_DIR="<CHROOT_DIR>"
TERMUX_HOME="<TERMUX_HOME>"
PERSIST_HELPER="${TERMUX_HOME}/.local/bin/debian-persist-mounts-root.sh"

if [ -x "$PERSIST_HELPER" ]; then
  "$PERSIST_HELPER" release || true
else
  umount -lf "$CHROOT_DIR/mnt/termux-home" 2>/dev/null || true
fi

umount -lf "$CHROOT_DIR/sdcard" 2>/dev/null || true
umount -lf "$CHROOT_DIR/sys" 2>/dev/null || true
umount -lf "$CHROOT_DIR/proc" 2>/dev/null || true
umount -lf "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount -lf "$CHROOT_DIR/dev" 2>/dev/null || true
echo "Debian chroot mounts released."
