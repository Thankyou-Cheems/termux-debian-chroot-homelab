# 公开仓库维护（去敏导出）

目标：从私有 `/opt/ops` 自动导出一个可公开分享的仓库，记录部署方案与架构，但不泄露敏感信息。

## 1. 一键导出

```bash
bash /opt/ops/scripts/export-public-repo.sh --output /opt/ops-public --force --init-git
```

## 2. 导出策略

1. 仅白名单复制控制面内容：`docs/`、`scripts/`、`deploy/`、`host/`、`services/portal/`、`env/`、`README.md` 等。
2. 强制排除敏感目录：
   - `secrets/live`
   - `backup-artifacts/latest`
   - `backup-artifacts/runs`
3. 对文本内容自动替换占位符：
   - `10.x.x.x -> <HOST_IP>`
   - `192.168.x.x / 172.16-31.x.x / 100.64-127.x.x -> <HOST_IP>`
   - `u0_aXX -> <TERMUX_USER>`
   - `<TERMUX_HOME> -> <TERMUX_HOME>`
   - `<CHROOT_DIR> -> <CHROOT_DIR>`
   - `<GITHUB_USER> -> <GITHUB_USER>`
   - `<DEPLOYMENT_REPO> -> <DEPLOYMENT_REPO>`
   - `UUID -> <UUID>`
   - 常见 key-value 密钥行（`token/password/secret/...`）-> `"<REDACTED>"`
4. `host/magisk/easytier/config/config.toml` 仅导出为 `config.toml.example`。
5. 导出后会执行 leak sentinel 扫描：若仍命中敏感标记，脚本会直接失败并阻止产物输出。

## 3. 推送公开仓库

```bash
cd /opt/ops-public
git add -A
git commit -m "docs: publish sanitized deployment architecture"
git remote add origin <public_repo_url>
git push -u origin main
```

## 4. 日常更新流程

1. 先在私有仓库完成变更并验证。
2. 再执行导出脚本覆盖 `/opt/ops-public`。
3. 检查 diff 后提交并推送公开仓库。
