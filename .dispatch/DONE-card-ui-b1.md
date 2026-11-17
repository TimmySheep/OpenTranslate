DONE card-ui-b1

## 完成内容

- `apple/OpenTranslate/Shared (App)/TranslateScreen.swift`：主界面改为共享单列布局，加入输入主卡、抓手与可展开历史面板，统一语言胶囊，保留结果页布局并让语言栏和动作栏持续显示；移除“按 Enter 完成”和空结果占位。加入 iOS 文件/照片入口与 macOS 键盘操作。
- `apple/OpenTranslate/Shared (App)/TranslationHistoryStore.swift`：新增持久化历史数据层。
- `apple/OpenTranslate/OpenTranslate.xcodeproj/project.pbxproj`：将历史数据层注册到 iOS 与 macOS App target。
- `apple/OpenTranslate/macOS (App)/AppDelegate.swift`：窗口最小尺寸设为 380×560。
- `scripts/test-app-state.sh`、`scripts/app-state-selftest/main.swift`：新增命令行状态层自测。
- `.dispatch/REPORT-card-ui-b1.md`：实现细节与交互报告。
- `logs/2026-11/2026-11-18-card-ui-b1.md`：项目开发日志。

## 四个门禁

1. `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (iOS)' -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO` — **exit 0**。
2. `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (macOS)' -destination 'generic/platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` — **exit 0**。
3. `bash scripts/test-app-state.sh` — **exit 0**，12 项自测全部 PASS。
4. `cd extension && pnpm build:safari` — **exit 0**。构建有 `options-app` 被跳过及 chunk 大于 500 kB 的警告，未阻止构建完成。

## 变异检验

- 将 `entries.insert(entry, at: 0)` 临时改为 `entries.append(entry)`：新增顺序与超上限淘汰最旧记录两项自测 FAIL，脚本 **exit 1（预期）**。
- 恢复插入最前后重跑：12 项全部 PASS，脚本 **exit 0**。

## 实现约束与未完成项

- Xcode 27 的显式模块可见性要求 `TranslationHistoryStore.swift` 显式 `import Combine` 才能使用 `ObservableObject/@Published`；因此数据层不是字面上的“只 import Foundation”。保留 `swiftc -parse-as-library` 命令行自测路径，状态门禁通过。
- 未在运行中的 iOS/macOS 窗口逐项进行手势点按验收；本轮验证覆盖双平台编译、状态自测、Safari 扩展构建与 diff 检查。
- 除上述运行时 GUI 验收限制外，任务门禁无未完成项；未 push、未合并、未打 TestFlight 包。
