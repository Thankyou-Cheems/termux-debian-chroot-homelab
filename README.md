# /opt/ops 运维仓库

`/opt/ops` 是 `/opt` 业务的 Git 控制面：

1. 管理部署、备份、恢复与巡检脚本。
2. 跟踪外层 Termux / Debian 启动维护脚本。
3. 配合 `/opt/apps`、`/opt/data`、`/opt/logs` 完成运行态与代码解耦。

## 仓库结构（精简）

1. `scripts/`：部署、备份、恢复、PM2、主机脚本导入/下发
2. `deploy/`：`cron` 与 `pm2` 模板
3. `host/`：Termux、Debian 与 Magisk(EasyTier) 启动维护脚本（Git 跟踪）
4. `secrets/`：敏感信息镜像（仅限私有仓库）
5. `docs/`：操作手册与架构文档
6. `services/portal/`：分流页静态站点源码（Git 跟踪）

## 常用命令

1. 启动/更新业务栈（默认不带 HomeAssistant）：`bash /opt/ops/scripts/pm2-start-business.sh`
2. 健康检查：`bash /opt/ops/scripts/pm2-check-business.sh`
3. 初始化/升级 HomeAssistant（uv 管理）：`bash /opt/ops/scripts/uv-install-homeassistant.sh`
4. 备份（默认同步并提交 `secrets/live` 与备份产物到 Git，且仓库内大文件仅保留最近 3 次）：`bash /opt/ops/scripts/backup.sh`
5. 恢复：`bash /opt/ops/scripts/restore.sh --bundle <bundle> --data <snapshot> --force-data`
6. 导入外层脚本：`bash /opt/ops/scripts/import-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk`
7. 回写外层脚本：`bash /opt/ops/scripts/install-host-scripts.sh --termux-home /mnt/termux-home --magisk-module-dir /data/adb/modules/easytier_magisk`
8. 迁移密钥到 `/opt/secrets` 并建立软链接：`bash /opt/ops/scripts/migrate-secrets-to-runtime.sh`
9. 同步密钥到 Git 跟踪目录：`bash /opt/ops/scripts/sync-secrets-repo.sh export`

网关子路径（`:8080`）：

1. `/mcs/`
2. `/asf/`
3. `/aria2/`
4. `/syncthing/`

HomeAssistant 按需启动：

1. 启用并拉起：`ENABLE_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-start-business.sh`
2. 强制巡检：`CHECK_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-check-business.sh`
3. 默认启用 cgroup 资源护栏（内存 high/max + OOM 优先回收）

Codex non-fakeip 防护：

1. 运行时脚本：`/usr/local/sbin/codex-fakeip-guard.sh`
2. Git 跟踪副本：`/opt/ops/host/debian/sbin/codex-fakeip-guard.sh`
3. 一次修复：`/usr/local/sbin/codex-fakeip-guard.sh once`
4. 守护重启：`pkill -f "codex-fakeip-guard.sh daemon"; nohup /usr/local/sbin/codex-fakeip-guard.sh daemon >/tmp/codex-fakeip-guard.nohup 2>&1 &`
5. 日志查看：`tail -n 50 /var/log/codex-fakeip-guard.log`

## 安全说明

1. `secrets/live` 包含真实敏感信息，只允许推送到私有仓库。
2. 推送前确认远程仓库可见性是 `private`，并限制协作者权限。

## 文档入口

1. 操作手册：`docs/OPERATIONS.md`
2. 架构说明：`docs/ARCHITECTURE.md`
3. 外层脚本说明：`host/README.md`
4. 公开仓库去敏导出：`docs/PUBLIC_REPO.md`
