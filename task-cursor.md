# 当前批次：同步 Bettbox v1.19.7（已验收）

- 范围：完整同步上游工具链、12 项构建矩阵、2 项 macOS 签名矩阵、17 文件产物契约与文档；补丁范围、完整测试、签名、公证和全量发布门禁均保留。
- 上游：v1.19.7 / `5df714e0d5f133f3a4146dc2b1adfb2311f5f0d0`。
- 已验证源码：`73a1a8b58f06d7cf48a4838e7fa37f86b605df96`；最终提交只追加 README 和本游标的验收记录，构建/测试/签名代码与已验证源码相同。
- 交付：`codex/sync-upstream-v1.19.7`，PR #4；整批保持一个提交。本批未合并、部署或发布，已发布版本仍为此前记录的 v1.19.4。
- 原始失败：run `40221624466` 在旧矩阵门禁失败；四个补丁应用成功，后续流程未运行。
- 第一次候选：run `40289168562` / `f53cc411eec5178809fe76f7203fdfc86ceb2edf`。旧矩阵/产物红→绿对照（基线 `99e0458457c4bc195bd7751be3b001d16d4ba720`）、完整测试、12 项构建、Linux 权限、Android 签名及 Intel Mac 公证通过；ARM Mac 的 notarytool 调用在 codesign 验证后挂起，至 90 分钟 job 超时取消。失败日志不能区分上传链路与服务响应阻塞。
- 公证修正：使用 Apple 文档支持的标准 S3 上传入口，为整个签名公证步骤设置 10 分钟上限；Accepted、staple、codesign 和 Gatekeeper 检查保留。notarytool 自带 timeout 仅限制结果轮询，不能覆盖整个上传过程。
- 第二次候选：run `40305356946` / `2f4b9723ef3e5d5f10c93b718eed876ea11a3840`。全部构建和签名公证通过；最终产物门禁拒绝了 4 个额外 Android .apk.idsig 辅助文件。修正上传范围为已验证的 APK，签名验证和严格产物门禁不变。
- 最终验收：run `40309585907` 为 success。补丁范围检查、完整 mihomo 测试、12 项构建、3 项 Linux 真实安装权限检查、Android 签名及两项 macOS 签名公证全部通过；最终产物检查、provenance/checksums 生成与候选保存成功，发布及故障 issue 更新步骤均 skipped。
- macOS 正向证据：ARM64、AMD64 均返回 Apple `Accepted`，staple/validate 成功；DMG 和其中 App 的 Gatekeeper 结果均为 `Notarized Developer ID`。
- 最终 artifact：`12645516676` / `validated-release-candidate`，绑定 run `40309585907` 和已验证源码。ZIP SHA-256 为 `7691d274d0d83624e293abca1e7786a69df31d2f2ecff13a1f8dde30df31c592`，下载后与 GitHub digest 一致。
- 产物审阅：4 APK、4 Windows 文件、2 DMG、7 Linux 文件，共 17 个非空同版号发行文件；另含源码归档、provenance、SHA256SUMS 和发行说明。19 条校验和逐项匹配、无重复条目、无 .idsig 混入；provenance 的上游 SHA、builder SHA、12 项矩阵与 4 个补丁哈希均一致。
- 留存：候选已保存到外接盘；GitHub artifact 元数据显示过期时间为 2026-10-27 10:43:13 UTC，实际期限以元数据为准。原始成功/失败日志与终态回执仅存工作区外私有目录。
- 验收边界：所有测试/构建/签名均在 GitHub-hosted runner 执行；本地仅审阅文件和校验下载产物。GUI/真实代理业务未验，不能据此宣称此前 Windows 用户端故障恢复。
- 等待与跟进：所有运行均通过唯一状态工具取得终态，观察 timeout 未被当作失败重建；只有取得真实失败并完成修正才启动下一完整候选。heartbeat `bettbox` 已在验收后通过 automation_update 删除，无需用户继续跟进。
- 唯一下一步：本批实现与验收已完成；PR 交付审阅，合并或发布须有后续授权。
