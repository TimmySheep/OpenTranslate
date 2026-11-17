# 语言选择器置顶按钮

- 影响代码：`apple/OpenTranslate/Shared (App)/TranslateScreen.swift` 的 `languageRow` 左侧圆形置顶按钮；更新自动检测、已置顶和未置顶图标/颜色/尺寸，保留现有置顶操作、选中行为和长按菜单。
- 验证：iOS `xcodebuild` exit 0；macOS `xcodebuild` exit 0；`bash scripts/test-app-state.sh` exit 0；`git diff --check` exit 0。
- 任务交付：`.dispatch/DONE-card-ui-b4.md`。
- 按任务卡要求不 push、不合并、不打包。
