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

不再单独应用 PR #2615，因为 #2627 的第一个提交已经包含同一修复。仓库中的四个 patch 最初针对 Bettbox 内置 mihomo v1.19.30 完成冲突移植，仍保留为四个独立源码提交。本次构建契约对齐 Bettbox v1.19.7（内置 mihomo v1.19.33）；补丁适用性和完整 mihomo 测试仍由每次工作流检查，不能仅凭补丁成功应用就认为功能通过验证。

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
5. 构建上游全部 12 个矩阵项，并在 GitHub-hosted Linux runner 上实际安装 DEB/RPM，检查 Core 的 0755 权限、capabilities 和打包的 Polkit 规则。
6. 签名 Android APK；签名、公证并 staple macOS DMG。
7. 只有全部矩阵和签名任务成功，且 17 个同版号发行文件完整、非空、没有额外文件后，才创建同版号 Release。
8. 发布 SHA256SUMS、SOURCE_PROVENANCE.json 和 patched source archive。

如果未来上游改动导致补丁冲突、上游矩阵与本仓库经过审核的矩阵不一致、任一平台失败或 Apple 公证失败，工作流不会发布残缺 Release，而会创建或更新一个自动化故障 Issue。矩阵变化必须先同步审核，避免新平台被静默漏构建。

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
| macOS | Apple Silicon | macos-26 |
| macOS | Intel amd64 | macos-26 |
| Linux | amd64 | ubuntu-22.04 |
| Linux | arm64 | ubuntu-24.04-arm |
| Linux | amd64 compatible | ubuntu-22.04 |

与 v1.19.7 上游保持一致：Flutter 3.47.7（Windows/Linux ARM runner 沿用上游 master channel）、Go 1.25.x / Compatible 1.24.x、Xcode 26、Rust stable、Java 17、Android NDK 28.2.13676358。macOS 构建和签名均使用 macos-26；运行最低版本为 macOS 12，不是 macOS 26。上游已移除独立 macOS Compatible 变体，Intel Core 统一使用 GOAMD64=v1；Windows/Linux Compatible 继续保留。

12 个构建项产出 17 个发行文件：4 个 APK、3 个 Windows 安装包和 1 个 Windows amd64-compatible portable ZIP、2 个 macOS DMG、7 个 Linux 文件（两个 amd64 变体各有 AppImage/DEB/RPM，arm64 只有 DEB）。Android 上传只收集已验证的 APK；签名工具生成的增量安装辅助 `.idsig` 文件不加入发行集合，APK 签名及验证不变。源码归档、provenance 和校验和在发行文件检查通过后加入。

## 签名状态

- Android：使用本仓库固定、长期一致的独立 keystore。第一次从上游官方签名 APK 迁移时，Android 可能要求先卸载原应用；此后本仓库版本之间可正常覆盖升级。
- macOS：两个 DMG 均使用 Developer ID Application 签名，提交 Apple notarization，必须返回 Accepted，再执行 staple、签名和 Gatekeeper 验证。整个签名公证步骤最多 10 分钟（包含上传），超时或失败不发布；`notarytool --timeout` 本身只限制结果轮询。上传使用 [Apple 文档支持的标准 S3 入口](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)，关闭 Transfer Acceleration。
- Windows：当前没有可用的 Authenticode 证书，安装包明确作为 unsigned 发布。
- Linux：沿用上游普通 AppImage、DEB 和 RPM 构建，不做代码签名。

工作流使用的私钥、密码和 App Store Connect API key 副本保存在 GitHub Actions encrypted repository secrets 中；仓库所有者另行保管 Git 外离线备份。任何凭据都不存在于 Git、Release、artifact 或日志。上游构建 job 不读取这些 secrets；签名在独立 job 中完成。

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

手动运行现有工作流时可设置 `validation_only=true`：完整执行构建、签名、公证和最终产物门禁，保存 `validated-release-candidate` artifact（请求保留 14 天，实际期限以 artifact 元数据为准），但不创建/覆盖 Release，也不关闭或更新正式发布故障 Issue。此模式也允许在同仓库候选分支上验证；仍需有权手动触发工作流，并使用独立签名 job，构建 job 不读取签名秘密。正式发布仍限定 main，所有前置任务必须成功。

一次性红→绿核对可同时传入 `regression_base`（旧 builder 的完整 commit SHA）；它在同一 hosted 运行中执行旧矩阵/产物检查并确认预期失败，然后执行候选回归和后续完整流程。不传该参数时不执行旧版对照，不增加定时发布的测试门禁。

发行目录检查在 GitHub-hosted Linux 上执行：`scripts/validate-release-assets.sh DIST_DIR v1.19.7`。回归测试命令为 `python3 -m unittest discover -s tests -v`，同样只在 GitHub workflow 执行。Linux 安装验证证明的是包的真实安装脚本与权限结果，不代替各平台的交互式 App/代理业务验收。

v1.19.7 同步批次已通过 [完整 hosted 验证](https://github.com/lovitus/Bettbox-persistent-pin/actions/runs/40309585907)，验证源码为 `73a1a8b58f06d7cf48a4838e7fa37f86b605df96`；之后仅补充文档记录。两项 Mac 公证均返回 Accepted，DMG/App 均通过 Gatekeeper；17 个发行文件及 19 条校验和已核对。旧矩阵、产物及 Linux 权限门禁的红→绿证据保留在 [首次候选运行](https://github.com/lovitus/Bettbox-persistent-pin/actions/runs/40289168562)。具体失败、修正及验收边界见 [当前任务记录](task-cursor.md)。

补丁有意保持为普通 format-patch，而不是维护一份完整 Bettbox fork。这样每次构建都能清楚记录上游 tag、上游 commit、补丁哈希和最终 patched-source commit。若未来上游已经合并该功能或相关代码发生冲突，应审核并刷新四个 patch，不能静默跳过其中某个提交。

尚未完成但有价值的签名维护项记录在 [postponed-tasks.md](postponed-tasks.md)。

## License

Builder 脚本和补丁按 GPL-3.0 发布；Bettbox 和 mihomo 的源码及构建产物继续遵守各自上游许可证。
