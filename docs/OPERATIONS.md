# 运维手册（最小可用）

## 1. 新增业务服务

1. 创建目录：`/opt/ops/services/<service_name>/`
2. 提交代码：
   - `cd /opt/ops`
   - `git add services/<service_name>`
   - `git commit -m "add service <service_name>"`

## 2. 部署服务

```bash
bash /opt/ops/scripts/deploy.sh --service <service_name> --ref main
```

部署后路径：

1. 发布目录：`/opt/apps/<service_name>/releases/<timestamp>/`
2. 当前版本：`/opt/apps/<service_name>/current`（软链接）

## 3. 代码和数据备份

```bash
bash /opt/ops/scripts/backup.sh
```

输出位置：

1. Git bundle：`/opt/backup/git-bundles/ops-<timestamp>.bundle`
2. 数据快照：`/opt/backup/data-snapshots/data-<timestamp>.tar.gz`
3. 备份前会自动执行一次密钥同步：`sync-secrets-repo.sh export`。
4. 备份后会自动同步到 Git 仓库内：`/opt/ops/backup-artifacts/runs/<timestamp>/`，`latest/*` 为指向最新一次的软链接。
5. 默认只保留最近 3 次仓库内大备份产物（可用 `--repo-artifacts-keep <count>` 调整）。
6. 默认会自动创建 Git 提交，仅包含：`backup-artifacts` 与 `secrets/live`。
7. 默认会自动重写 Git 历史，移除被轮转掉的旧 `backup-artifacts/runs/*` 大文件路径（等价于 `git filter-repo` 清理思路，要求仓库无未提交跟踪改动）。
8. 若仓库有远程，历史重写后推送需要使用 `git push --force-with-lease`。
9. 可用 `--skip-repo-history-prune` 临时跳过历史瘦身（会导致仓库体积增长）。
10. 默认会清理 `data-snapshots/` 下超过保留期的临时目录（可用 `--keep-temp-dirs` 禁用）。
11. 密钥已迁移后，`data` 快照只保存 `/opt/data` 下的软链接，真实密钥依赖 Git 中的 `secrets/live`。
12. `data` 快照默认排除以下大体积/可再生目录：`/opt/data/syncthing/sync`、`/opt/data/aria2/data`、`/opt/data/transmission/data`、`/opt/data/transmission/incomplete`、`/opt/data/filebrowser/root`（该目录是 bind mount 聚合视图）。

如需临时跳过密钥同步：

```bash
bash /opt/ops/scripts/backup.sh --skip-secrets-sync
```

如需临时不把备份产物落到仓库：

```bash
bash /opt/ops/scripts/backup.sh --skip-repo-artifacts-sync
```

如需临时不自动创建 Git 提交：

```bash
bash /opt/ops/scripts/backup.sh --skip-repo-backup-commit
```

如需临时禁用仓库大文件历史瘦身：

```bash
bash /opt/ops/scripts/backup.sh --skip-repo-history-prune
```

## 4. 代码和数据恢复

```bash
bash /opt/ops/scripts/restore.sh \
  --bundle /opt/backup/git-bundles/ops-<timestamp>.bundle \
  --data /opt/backup/data-snapshots/data-<timestamp>.tar.gz \
  --ref main \
  --force-data
```

说明：

1. `--force-data` 会在恢复前把旧 `/opt/data` 移到 `/opt/data.pre-restore-<timestamp>`。
2. 若只恢复代码或只恢复数据，可只传 `--bundle` 或 `--data`。
3. 若需要恢复密钥，先恢复仓库，再执行 `bash /opt/ops/scripts/sync-secrets-repo.sh import`。
4. 若需恢复 HomeAssistant 运行时，恢复后执行 `bash /opt/ops/scripts/uv-install-homeassistant.sh`，再 `pm2 restart homeassistant`。

## 5. 生产发布建议

1. 主分支固定为 `main`，只保留可上线代码。
2. 每次上线打标签，例如：`prod-20260224-1500`。
3. 回滚时直接部署历史标签：
   - `bash /opt/ops/scripts/deploy.sh --service <service_name> --ref prod-20260224-1500`

## 6. 自动备份（可选）

先安装 cron：

```bash
apt-get update && apt-get install -y cron
```

再安装计划任务模板：

```bash
bash /opt/ops/scripts/install-cron.sh
```

## 7. PM2 启动与巡检

初始化或升级 HomeAssistant（uv 管理，不使用 venv）：

```bash
bash /opt/ops/scripts/uv-install-homeassistant.sh
```

启动（或更新）业务进程：

```bash
bash /opt/ops/scripts/pm2-start-business.sh
```

说明：

1. `syncthing` 默认纳入 PM2 常驻，配置目录：`/opt/data/syncthing/config`，以专用系统用户 `syncthing` 运行，GUI 仅监听 `127.0.0.1:8384`，通过 Caddy 子路径暴露。
2. 默认不会启动 HomeAssistant（避免移动端高负载卡顿）。
3. 需要时显式开启：`ENABLE_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-start-business.sh`。
4. 默认启用 HomeAssistant 资源保护（`pm2-run-homeassistant.sh`）：
   - `memory.high=1572864000`（约 1500 MiB）
   - `memory.max=2147483648`（约 2048 MiB）
   - `memory.swap.max=0`（禁用该服务 swap，防止整机抖动）
   - `oom_score_adj=300`（低内存时允许优先回收 HA）
   - PM2 `max_memory_restart=1900M`
5. 可在 `/opt/ops/deploy/pm2/ecosystem.business.config.js` 的 `homeassistant.env` 中调整阈值。

健康检查：

```bash
bash /opt/ops/scripts/pm2-check-business.sh
```

如需放宽冷启动等待时间：

```bash
CHECK_TIMEOUT_SEC=60 bash /opt/ops/scripts/pm2-check-business.sh
```

如需强制包含 HomeAssistant 检查：

```bash
CHECK_HOMEASSISTANT=1 bash /opt/ops/scripts/pm2-check-business.sh
```

查看 HomeAssistant cgroup 占用（字节）：

```bash
cat /sys/fs/cgroup/opt-homeassistant/memory.current
cat /sys/fs/cgroup/opt-homeassistant/memory.high
cat /sys/fs/cgroup/opt-homeassistant/memory.max
cat /sys/fs/cgroup/opt-homeassistant/memory.swap.max
```

查看状态与日志：

```bash
pm2 ls
pm2 logs --lines 100
```

网关入口与子目录：

1. `/`：分流首页
2. `/mcs/`：MCSManager
3. `/asf/`：ASF
4. `/aria2/`：AriaNg
5. `/syncthing/`：Syncthing Web GUI
6. `/files/`：统一文件面板（aria2 / Transmission / Syncthing / Termux Home）
7. HomeAssistant：`http://<host>:8123/`（按需启用）
8. Tinyproxy（Docker 拉镜像代理）：`<HOST_IP>:18888`（默认允许 `<HOST_IP>/24`）

分流页源码路径：

1. `/opt/ops/services/portal/index.html`（Git 管理）

日志路径约定：

1. PM2 stdout/stderr：`/opt/logs/*.out.log`、`/opt/logs/*.err.log`
2. 业务运行时日志：`/opt/apps/*/current/logs -> /opt/logs/*`（软链接）
3. HomeAssistant 配置与状态目录：`/opt/data/homeassistant`
4. Syncthing 配置目录：`/opt/data/syncthing/config`
5. Syncthing 状态目录：`/opt/data/syncthing/state`
6. Syncthing 同步目录：`/opt/data/syncthing/sync`（默认不打入 `backup.sh` 的 data 快照）
7. Aria2 下载目录：`/opt/data/aria2/data`（默认不打入 `backup.sh` 的 data 快照）
8. Transmission 下载目录：`/opt/data/transmission/data`（默认不打入 `backup.sh` 的 data 快照）
9. Transmission 未完成目录：`/opt/data/transmission/incomplete`（默认不打入 `backup.sh` 的 data 快照）
10. FileBrowser 数据目录：`/opt/data/filebrowser`（其中 `root/` 为 bind mount 聚合视图，默认不打入 `backup.sh` 的 data 快照）
11. Tinyproxy 配置与日志：`/opt/data/tinyproxy/tinyproxy.conf`、`/opt/logs/tinyproxy/`

## 8.1 当前手机代理基线

当前 Android 侧实际运行的是 Mihomo/Meta 风格订阅，基线订阅地址：

`http://<HOST_IP>:18080/baa3598c98ea835973bf0a57519ef0df-mobile.yaml`

关键本地监听：

1. `127.0.0.1:7890`：mixed proxy
2. `127.0.0.1:1053`：本地 DNS
3. `tun0`：代理 TUN 接口

兼容性说明：

1. 该代理与 `/opt` 业务栈当前端口无直接冲突：`8080`、`6800`、`8384`、`9091`、`18888` 可并存。
2. 该代理启用了 `fake-ip`（`198.18.0.1/16`），Codex 访问稳定性依赖 `codex-fakeip-guard.sh` 的 `/etc/hosts` 修正逻辑。
3. 该代理与 EasyTier 可共存，但依赖 `host/magisk/easytier/vpn_recover.sh` 持续修复上游 peer 路由，避免 TUN 抢走 EasyTier 关键出站路径。
4. 如需额外启动第二个 Mihomo/Meta/Clash 内核，必须先避开 `7890` 和 `1053`，否则会直接端口冲突。

## 9. Docker 代理开关（给 .1 使用）

在 `.4` 上，tinyproxy 由 PM2 常驻，默认监听 `<HOST_IP>:18888`。

在 `.1` 上可按需切换 Docker 是否走代理：

启用代理（`.1` 执行）：

```bash
bash /opt/ops/scripts/docker-proxy-enable.sh http://<HOST_IP>:18888
```

禁用代理（`.1` 执行）：

```bash
bash /opt/ops/scripts/docker-proxy-disable.sh
```

说明：

1. 上述两个脚本作用于 `.1` 的 `docker.service`，写入或删除 `/etc/systemd/system/docker.service.d/proxy.conf`。
2. 每次切换都会自动 `systemctl daemon-reload && systemctl restart docker`。
3. 若 `.1` 没有这两个脚本，可从 `.4:/opt/ops/scripts/` 拷贝后执行。

## 9. Caddy 配置维护规则

1. Git 管模板源文件位于 `/opt/ops/deploy/caddy/Caddyfile`。
2. 运行态文件位于 `/opt/data/caddy/Caddyfile` 与 `/opt/data/caddy/upstreams.env`。
3. 当运行态 `Caddyfile` 缺失时，`pm2-start-business.sh` 会优先从 Git 模板初始化。
4. 当前 `upstreams.env` 关键项：`ASF_UPSTREAM`、`SYNCTHING_UPSTREAM`、`FILEBROWSER_UPSTREAM`。
5. `/opt/apps/caddy/current/Caddyfile` 与 `/opt/apps/caddy/current/upstreams.env` 仅作为兼容入口，必须保持为软链接。
4. 若误改成普通文件，执行 `bash /opt/ops/scripts/pm2-start-business.sh` 会自动恢复为软链接并同步上游配置。

## 10. 外层脚本版本管理（Termux + Debian）

导入当前运行中的脚本到 Git 工作区：

```bash
bash /opt/ops/scripts/import-host-scripts.sh
```

如 Termux Home 已挂载到 Debian（例如 `/mnt/termux-home`）：

```bash
bash /opt/ops/scripts/import-host-scripts.sh \
  --termux-home /mnt/termux-home \
  --magisk-module-dir /data/adb/modules/easytier_magisk
```

把 Git 中跟踪的脚本回写到运行路径：

```bash
bash /opt/ops/scripts/install-host-scripts.sh
```

同样可指定挂载路径：

```bash
bash /opt/ops/scripts/install-host-scripts.sh \
  --termux-home /mnt/termux-home \
  --magisk-module-dir /data/adb/modules/easytier_magisk
```

当前外层脚本纳管清单：

1. `00-startup.sh`
2. `start-debian`
3. `start-debian-root.sh`
4. `stop-debian`
5. `stop-debian-root.sh`
6. `debian-persist-mounts-root.sh`
7. `codex-start-sshd.sh`
8. `codex-fakeip-guard.sh`
9. `easytier_magisk/service.sh`
10. `easytier_magisk/easytier_core.sh`
11. `easytier_magisk/vpn_recover.sh`
12. `easytier_magisk/hotspot_iprule.sh`（若模块存在）
13. `easytier_magisk/config/config.toml`（若模块存在）
14. `easytier_magisk/config/command_args`（若模块存在）

持久挂载联动说明：

1. `start-debian-root.sh` 会调用 `debian-persist-mounts-root.sh ensure`，确保 `TERMUX_HOME` 绑定到 chroot 的 `/mnt/termux-home`。
2. `stop-debian-root.sh` 会调用 `debian-persist-mounts-root.sh release` 后再释放其它挂载。

说明：

1. Termux 默认路径是 `<TERMUX_HOME>`，可用 `--termux-home` 覆盖。
2. EasyTier Magisk 默认路径是 `/data/adb/modules/easytier_magisk`，可用 `--magisk-module-dir` 覆盖。
3. 安装脚本会先备份旧文件到 `/opt/backup/host-script-backups/<timestamp>/`。
4. 当前环境看不到 Termux 或 Magisk 路径时，导入会跳过缺失文件，不会中断。
5. 若看不到 Magisk 路径，可通过 `--termux-cache-dir` 从 Termux 缓存副本导入 EasyTier 脚本。

## 11. 密钥迁移与私有仓库备份

一次性迁移敏感文件到 `/opt/secrets` 并保持原路径可用：

```bash
bash /opt/ops/scripts/migrate-secrets-to-runtime.sh
```

日常把运行时密钥同步到 Git 跟踪目录：

```bash
bash /opt/ops/scripts/sync-secrets-repo.sh export
```

从 Git 跟踪目录回写到运行时：

```bash
bash /opt/ops/scripts/sync-secrets-repo.sh import
```

说明：

1. 运行时密钥目录：`/opt/secrets`。
2. Git 跟踪镜像目录：`/opt/ops/secrets/live`。
3. 推送前确认远程仓库必须是私有仓库。
