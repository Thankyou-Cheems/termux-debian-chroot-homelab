# termux-debian-chroot-homelab

公开版部署蓝图：Termux + Debian chroot + PM2 + Caddy 的便携式 HomeLab 运维方案。

本仓库是去敏后的公开镜像，只保留可复用的架构、脚本和文档模板。

## 仓库定位

1. 记录部署架构与运维流程。
2. 提供可复用脚本（部署、备份、恢复、巡检）。
3. 提供 Termux / Debian / Magisk（EasyTier）脚本模板。
4. 提供网关分流页模板（`services/portal/`）。

## 不包含的内容

1. 真实密钥与账号（例如 `secrets/live`）。
2. 备份二进制产物（例如 `backup-artifacts/runs/*`、`backup-artifacts/latest/*`）。
3. 设备专属标识与网络实值（IP、设备 ID、peer 地址、network secret）。

## 占位符约定

1. `<HOST_IP>`
2. `<TERMUX_USER>`
3. `<TERMUX_HOME>`
4. `<CHROOT_DIR>`
5. `<NETWORK_SECRET>`
6. `<PEER_IP>`

## 文档入口

1. 架构说明：`docs/ARCHITECTURE.md`
2. 操作手册：`docs/OPERATIONS.md`
3. Host 脚本说明：`host/README.md`
4. 公开导出说明：`PUBLIC_EXPORT.md`

## 快速自检（防止敏感信息误提交）

```bash
grep -RInE "ghp_|github_pat_|AKIA|AIza|xox[baprs]-|-----BEGIN .*PRIVATE KEY-----|password\\s*=|token\\s*=|secret\\s*=" .
grep -RInE "u0_a[0-9]+|/data/local/chroot/debian|/data/data/com.termux/files/home|([0-9]{1,3}\\.){3}[0-9]{1,3}" .
```

## 说明

1. 如需真实可运行配置，请在私有仓库维护并导出到公开仓库。
2. 旧仓库 `termux-proot-services` 已标记为 legacy，不再维护。
