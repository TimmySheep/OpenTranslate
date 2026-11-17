# OpenTranslate TestFlight iOS build 4

- 日期：2026-11-14
- 构建：iOS 1.0.1 (4)，App Store Connect build `88138933-933d-4b91-b771-fa6aa0e6f81a`
- 状态：`VALID`；已关联内部测试组“内部测试”；`usesNonExemptEncryption=false`。
- 签名：`Apple Distribution: Tianwei Huang (JY5U4D6JD3)`。
- 分发 profiles：`OpenTranslate iOS App Store`（UUID `78ac1b37-833b-4b3b-8ea4-eddee16fa3b6`）和 `OpenTranslate Safari Extension App Store`（UUID `f9b8d14b-887f-4f30-86e5-9cf5c3840bbb`）。两者均含 `group.net.timhuang.opentranslate` 与 iCloud KVS entitlement。
- Xcode 自动签名已成功同步 App Groups 与 iCloud KVS 能力。ASC 中旧的两个无效同名 profile 已在备份到 `/tmp/profiles-backup/` 后替换；新 profiles 为 ACTIVE，绑定 Apple Distribution 证书 SHA-1 `34ACE569949282FDCF1A8248073F430B4CE5BC5A`。
- 归档前已运行 `scripts/build-safari.sh` 和 `scripts/sync-resources.sh`，并在 Aqua launchd 会话中归档、导出和上传。
- 首次上传因已批准的 1.0 版本关闭而被拒。通过归档命令临时指定 `MARKETING_VERSION=1.0.1` 后成功；没有修改仓库项目文件。
- 没有 git push。
