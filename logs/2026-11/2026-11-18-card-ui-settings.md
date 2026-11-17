# 卡片 UI 与原生生成设置

- 影响代码：`apple/OpenTranslate/Shared (App)/TranslateScreen.swift`、新建 `NativeGenerationSettings.swift`、Xcode 项目文件及状态自测脚本。设置使用 App 本地 `UserDefaults`，支持系统提示词及占位符、温度和最大输出 tokens，并扩展默认目标语言选项；请求集成统一使用 `max_tokens`，值为 0 时省略。“恢复默认”填入的默认文本也保留默认图片翻译指令。
- UI 审计：完成搜索框、关闭按钮、选择器卡片、粘贴胶囊、底部动作栏和常驻语言栏尾项。
- 验证：iOS 与 macOS `xcodebuild`、`bash scripts/test-app-state.sh`、`pnpm build:safari` 均 exit 0。空白提示词回退变异测试红测 exit 1（目标用例 FAIL），恢复后绿测 exit 0。Safari 构建有 `options-app` entrypoint skipped 与部分 chunk 超 500 kB 的非阻断 warning。
- 限制：尚未逐家核实 provider 对 `max_tokens` / `max_completion_tokens` 的差异；生成设置不与 Safari 扩展同步。未制作 TestFlight 包、未 push、未合并。
- 任务报告：`.dispatch/DONE-card-ui-b3.md` 与 `.dispatch/REPORT-card-ui-b3.md`。
