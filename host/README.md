# Host 脚本目录

这里仅存放外层启动/维护脚本的 Git 副本，不直接作为运行目录。

1. `termux/boot/`：Termux:Boot 脚本（如 `00-startup.sh`）
2. `termux/bin/`：Termux 用户/Root 脚本（如 `start-debian-root.sh`、`stop-debian-root.sh`、`debian-persist-mounts-root.sh`）
3. `debian/sbin/`：Debian Root 脚本（如 `codex-start-sshd.sh`、`codex-fakeip-guard.sh`）
4. `magisk/easytier/`：Magisk EasyTier 模块脚本（如 `service.sh`、`easytier_core.sh`、`vpn_recover.sh`）

同步命令：

1. 导入运行层脚本：`bash /opt/ops/scripts/import-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk`
2. 下发仓库脚本到运行层：`bash /opt/ops/scripts/install-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk`
3. 若 Debian 内看不到 `/data/adb`，导入会自动回退到 `--termux-cache-dir`（默认 `<termux-home>/.cache`）中的 EasyTier 副本。

详细流程见 `/opt/ops/docs/OPERATIONS.md` 第 9 节。
