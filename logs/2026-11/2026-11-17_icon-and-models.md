# Icon Composer 与模型列表

- 影响：`apple/OpenTranslate/Shared (App)/TranslateScreen.swift`、App 图标工程资源与 Info.plist；详细实现和验收证据见 [任务报告](../../.dispatch/REPORT-icon-and-models.md)。
- 模型列表：增加 `/models` 请求、响应解析、缓存、可搜索选择列表及明确错误提示；未改翻译链路。
- 图标：`.icon` 已接入 iOS/macOS App target 并编译入 `Assets.car`。但模板只有空 `groups`，目前 `assetutil` 验证 IconImageStack 为单层，不能认定玻璃石前景已接入；具体卡点与完整 actool 输出见任务报告。
- 验证：iOS、macOS 不签名 `xcodebuild` 均退出码 0；`git diff --check` 通过。
- 无 commit/push、无 build 号变更。
