DONE card-ui-b2

## 改动文件

- `apple/OpenTranslate/Shared (App)/TranslateScreen.swift`：结果详情页、操作菜单、收藏入口、历史/已保存分段、语言选择器和置顶交互。
- `apple/OpenTranslate/Shared (App)/TranslationHistoryStore.swift`：历史记录加入 `isSaved` 与 `setSaved(id:saved:)`。
- `apple/OpenTranslate/Shared (App)/LanguagePinStore.swift`：新增基于 `UserDefaults` 的有序语言置顶存储。
- `apple/OpenTranslate/OpenTranslate.xcodeproj/project.pbxproj`：仅注册新 Swift 文件。
- `scripts/app-state-selftest/main.swift`、`scripts/test-app-state.sh`：扩充状态测试及编译置顶存储。
- `.dispatch/DONE-card-ui-b2.md`、`.dispatch/REPORT-card-ui-b2.md`：本批次交付说明。

## 验收门禁

| 命令 | 退出码 | 结果 |
|---|---:|---|
| `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (iOS)' -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO` | 0 | `BUILD SUCCEEDED` |
| `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (macOS)' -destination 'generic/platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` | 0 | `BUILD SUCCEEDED` |
| `bash scripts/test-app-state.sh` | 0 | 历史、收藏、置顶自测逐条 PASS |
| `cd extension && pnpm build:safari` | 0 | 构建成功；输出仍提示跳过 `options-app`，并有大 chunk 警告 |

## 置顶变异检验

- 将新置顶从数组头部改为追加到末尾：顺序用例按预期失败，退出码 1；恢复后状态自测退出码 0。
- 将持久化读回的置顶顺序改为字母序：重启顺序与旧 key 兼容相关用例按预期失败，退出码 1；恢复后状态自测退出码 0。

## 未完成项与限制

- 未进行 iOS/macOS 运行时 GUI 点按验收；本批次规定的四项构建/自测门禁均已通过。
- 没有目标罗马字专用字段，因此不从 `ipa` 推测目标语言罗马字；旧历史记录也不伪造词典详情。
- 未 push、未合并、未打 TestFlight 包。
