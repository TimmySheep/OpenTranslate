DONE card-ui-b3

## 修改文件

- `apple/OpenTranslate/Shared (App)/TranslateScreen.swift`
- `apple/OpenTranslate/Shared (App)/NativeGenerationSettings.swift`（新建）
- `apple/OpenTranslate/OpenTranslate.xcodeproj/project.pbxproj`（仅注册新 Swift 文件）
- `scripts/test-app-state.sh`
- `scripts/app-state-selftest/main.swift`
- `.dispatch/DONE-card-ui-b3.md`
- `.dispatch/REPORT-card-ui-b3.md`
- `docs/PROJECT-STATE.md`（仅追加本轮小节）

## 四个门禁

1. `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (iOS)' -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO` — **exit 0**
2. `cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (macOS)' -destination 'generic/platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` — **exit 0**
3. `bash scripts/test-app-state.sh` — **exit 0**，新增设置用例逐条 PASS。
4. `cd extension && pnpm build:safari` — **exit 0**。

## 变异检验

- 红：把空值回退临时改为返回空串，`bash scripts/test-app-state.sh` **exit 1**；第 2 条“仅空白与换行提示词回退到内置默认”明确 FAIL（默认值与 reset 用例也随之失败）。
- 绿：恢复空值回退后再次运行同一脚本，**exit 0**；新增用例全部 PASS。

## 审计尾项

- 搜索框、关闭按钮、选择器卡片：核对后已符合尺寸、颜色和圆角规格。
- 粘贴胶囊移入底部动作栏左侧；无剪贴板文字时不渲染、不占位。
- 底部动作栏按 86pt 麦克风、44pt 侧控件、12pt 间距布置，麦克风严格居中。
- 输入态与结果态语言栏均固定在底部并共用相同横向约束。
- 主卡、结果页、浅深色选择器、置顶顺序及历史/收藏数据层核对已满足；详见报告中的 `file:line`。

## 未完成项

- 本轮必做项无未完成。
- Safari 构建有非阻断提示：`options-app` entrypoint skipped，且有 chunk 超过 500 kB；构建仍 exit 0。
- 未制作 TestFlight 包、未 push、未合并。
