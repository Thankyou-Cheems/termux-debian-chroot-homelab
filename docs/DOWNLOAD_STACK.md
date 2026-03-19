# 下载栈说明

这套下载栈现在由 `aria2 + AriaNg + Transmission + bt-trackers + Caddy + PM2` 组成。

入口：

1. `http://<host>:8080/aria2/`：AriaNg，适合 HTTP/HTTPS/FTP、磁力和轻量 BT。
2. `http://<host>:8080/transmission/`：Transmission Web，适合长时间 BT 做种和复杂队列。
3. `http://<host>:8080/jsonrpc`：Aria2 RPC。

核心路径：

1. Aria2 下载目录：`/opt/data/aria2/data`
2. Transmission 下载目录：`/opt/data/transmission/data`
3. Transmission 未完成目录：`/opt/data/transmission/incomplete`
4. Transmission 监视目录：`/opt/data/transmission/watch`
5. Tracker 列表：`/opt/data/bt-trackers/trackers-best.txt`
6. Transmission RPC 账号：`/opt/secrets/transmission/rpc-username.txt`
7. Transmission RPC 密码：`/opt/secrets/transmission/rpc-password.txt`

常用命令：

```bash
pm2 ls
pm2 logs transmission --lines 100
pm2 logs bt-trackers --lines 100
bash /opt/ops/scripts/update-bt-trackers.sh
bash /opt/ops/scripts/pm2-start-business.sh
bash /opt/ops/scripts/pm2-check-business.sh
```

说明：

1. `bt-trackers` 进程会每 6 小时自动刷新一次 tracker，并同步到 Aria2 和 Transmission。
2. Transmission 开启了 `watch-dir`，把 `.torrent` 文件放到 `/opt/data/transmission/watch` 会自动入队。
3. Termux 启动脚本已经包含 `termux-wake-lock` 调用，锁屏后只要系统没有杀掉 Termux，下载会继续。
4. 安卓侧还需要把 `Termux` 和 `Termux:Boot` 设为“不受电池优化限制”，否则厂商省电策略仍可能断后台。
