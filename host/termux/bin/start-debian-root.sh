#!/system/bin/sh
set -eu
CHROOT_DIR="<CHROOT_DIR>"
TERMUX_HOME="<TERMUX_HOME>"
PERSIST_HELPER="${TERMUX_HOME}/.local/bin/debian-persist-mounts-root.sh"

is_mounted() {
  awk -v m="$1" '$2==m { found=1 } END { exit !found }' /proc/mounts
}

mount_if_needed() {
  SRC="$1"
  DST="$2"
  if ! is_mounted "$DST"; then
    mount --bind "$SRC" "$DST"
  fi
}

if [ ! -x "$CHROOT_DIR/bin/bash" ]; then
  echo "Debian not installed at $CHROOT_DIR" >&2
  exit 1
fi

mkdir -p \
  "$CHROOT_DIR/dev" \
  "$CHROOT_DIR/dev/pts" \
  "$CHROOT_DIR/proc" \
  "$CHROOT_DIR/sys" \
  "$CHROOT_DIR/sdcard" \
  "$CHROOT_DIR/mnt/termux-home"

mount_if_needed /dev "$CHROOT_DIR/dev"
mount_if_needed /dev/pts "$CHROOT_DIR/dev/pts"
if ! is_mounted "$CHROOT_DIR/proc"; then
  mount -t proc proc "$CHROOT_DIR/proc"
fi
mount_if_needed /sys "$CHROOT_DIR/sys"
if [ -d /sdcard ]; then
  mount_if_needed /sdcard "$CHROOT_DIR/sdcard" || true
fi
if [ -x "$PERSIST_HELPER" ]; then
  "$PERSIST_HELPER" ensure || true
elif [ -d "$TERMUX_HOME" ]; then
  mount_if_needed "$TERMUX_HOME" "$CHROOT_DIR/mnt/termux-home" || true
fi

cp /system/etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true

export TERM="${TERM:-xterm-256color}"
BASE_ENV="HOME=/root TERM=$TERM PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ "$#" -gt 0 ]; then
  exec chroot "$CHROOT_DIR" /usr/bin/env -i $BASE_ENV /bin/bash -lc "$*"
else
  exec chroot "$CHROOT_DIR" /usr/bin/env -i $BASE_ENV /bin/bash -l
fi
