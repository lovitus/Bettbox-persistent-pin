# Bettbox Persistent Pin Builder

这个仓库自动跟随 [appshubcc/Bettbox](https://github.com/appshubcc/Bettbox) 的最新稳定 Release，把 [MetaCubeX/mihomo PR #2627](https://github.com/MetaCubeX/mihomo/pull/2627) 的完整四个提交移植到 Bettbox 内置 core，然后构建并发布 Bettbox 的完整上游平台矩阵。

应用内的 GitHub 入口、检查更新接口和安装包下载地址都会改为：

https://github.com/lovitus/Bettbox-persistent-pin

## 补丁边界

只应用 PR #2627 的四个提交，顺序保持不变：

1. ca3a4ac8 — 避免在仍有可用节点时选择测速超时节点
2. c4359c7f — 为 url-test 和 fallback 增加 persistent pin
3. 67a90dd2 — 增加 persistent pin 自动解除阈值
4. 6b84cc05 — 补充 persistent pin 计数器日志

不再单独应用 PR #2615，因为 #2627 的第一个提交已经包含同一修复。仓库中的四个 patch 是针对 Bettbox 当前内置 mihomo v1.19.30 完成冲突移植后的版本，仍保留为四个独立提交。

可在 url-test 或 fallback 代理组中使用：

    persistent-pin: true
    pin-unhealthy-log-interval: 10
    persistent-pin-auto-unfix-threshold: 10

## 自动化流程

工作流每天检查一次 Bettbox 最新稳定 Release，也支持手动强制重建。它会：

1. 解析上游最新稳定 tag，并克隆该 tag 的精确源码。
2. 按顺序应用四个 core patch。
3. 将应用内仓库常量和 About 页面链接改到本仓库。
4. 验证只改动经过审核的 9 个文件，并运行完整 mihomo 测试。
5. 构建上游全部 13 个矩阵项。
6. 签名 Android APK；签名、公证并 staple macOS DMG。
7. 只有全部矩阵和签名任务成功后才创建同版号 Release。
8. 发布 SHA256SUMS、SOURCE_PROVENANCE.json 和 patched source archive。

如果未来上游改动导致补丁冲突、任一平台失败或 Apple 公证失败，工作流不会发布残缺 Release，而会创建或更新一个自动化故障 Issue。

## 完整构建矩阵

| 平台 | 架构/变体 | Runner |
|---|---|---|
| Android | arm64-v8a | ubuntu-24.04 |
| Android | x86_64 | ubuntu-24.04 |
| Android | armeabi-v7a | ubuntu-24.04 |
| Android | universal | ubuntu-24.04 |
| Windows | amd64 | windows-2022 |
| Windows | arm64 | windows-11-arm |
| Windows | amd64 compatible | windows-2022 |
| macOS | Apple Silicon | macos-15 |
| macOS | Intel amd64 | macos-15 |
| macOS | Intel amd64 compatible | macos-15 |
| Linux | amd64 | ubuntu-22.04 |
| Linux | arm64 | ubuntu-24.04-arm |
| Linux | amd64 compatible | ubuntu-22.04 |

## 签名状态

- Android：使用本仓库固定、长期一致的独立 keystore。第一次从上游官方签名 APK 迁移时，Android 可能要求先卸载原应用；此后本仓库版本之间可正常覆盖升级。
- macOS：使用 Developer ID Application 签名，提交 Apple notarization，并对 DMG 执行 staple 与 Gatekeeper 验证。
- Windows：当前没有可用的 Authenticode 证书，安装包明确作为 unsigned 发布。
- Linux：沿用上游普通 AppImage、DEB 和 RPM 构建，不做代码签名。

所有私钥、密码和 App Store Connect API key 仅保存在 GitHub Actions encrypted repository secrets 中，不存在于 Git、Release、artifact 或日志。上游构建 job 不读取这些 secrets；签名在独立 job 中完成。

## Repository secrets

工作流需要以下 Actions Secrets：

- KEYSTORE
- KEY_ALIAS
- STORE_PASSWORD
- KEY_PASSWORD
- MACOS_CERTIFICATE_P12
- MACOS_CERTIFICATE_PASSWORD
- MACOS_SIGN_IDENTITY
- APP_STORE_CONNECT_API_KEY_P8
- APP_STORE_CONNECT_KEY_ID
- APP_STORE_CONNECT_ISSUER_ID

二进制 keystore、P12 和 P8 均以无换行 Base64 保存。

## 维护说明

补丁有意保持为普通 format-patch，而不是维护一份完整 Bettbox fork。这样每次构建都能清楚记录上游 tag、上游 commit、补丁哈希和最终 patched-source commit。若未来上游已经合并该功能或相关代码发生冲突，应审核并刷新四个 patch，不能静默跳过其中某个提交。

尚未完成但有价值的签名维护项记录在 [postponed-tasks.md](postponed-tasks.md)。

## License

Builder 脚本和补丁按 GPL-3.0 发布；Bettbox 和 mihomo 的源码及构建产物继续遵守各自上游许可证。
