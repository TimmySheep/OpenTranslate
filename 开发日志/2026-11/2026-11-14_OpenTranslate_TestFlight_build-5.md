# OpenTranslate TestFlight iOS build 5

- 日期：2026-11-14
- 构建：iOS 1.0.1 (5)，App Store Connect build `3932b2bf-8845-49d9-b9ce-b70e1021d0c1`；altool delivery UUID 相同。
- 状态：`VALID`；已加入内部测试组“内部测试” (`8345138c-7bcb-4e6a-bc9c-20e4efd30e57`)；`usesNonExemptEncryption=false`。
- 版本提交：`4afdb28` (`Bump TestFlight build to 5`)，只修改 `project.pbxproj` 中 8 个 `CURRENT_PROJECT_VERSION`；均为 5，`MARKETING_VERSION` 保持 1.0.1。未 push。
- 构建前运行 `scripts/build-safari.sh` 和 `scripts/sync-resources.sh`。Xcode 工程已有 settings 文件夹引用，归档日志确认复制 settings 至 App；IPA 内存在 `Payload/OpenTranslate.app/settings/options-app.html`。
- 归档和导出通过 `LimitLoadToSessionType=Aqua` 的 `gui/501` launchd job 执行，archive/export 均成功。
- 上传：`xcrun altool --upload-app` 明确返回 `UPLOAD SUCCEEDED with no errors`。IPA 的 `Info.plist` 为版本 1.0.1 (5)，包含 `Assets.car`；`assetutil` 解析到 `AppIcon` 1024px rendition。
- ASC API 回读：build 5 为 `VALID`，`usesNonExemptEncryption=false`，并确认与目标内部测试组关联。
- 没有修改其他源码文件，也没有 git push。
