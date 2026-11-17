DONE card-ui-b4

## 改动

- `apple/OpenTranslate/Shared (App)/TranslateScreen.swift:1529-1553`：仅调整语言选择器行左侧按钮。检测语言显示 16pt 蓝色 sparkles 且禁用；已置顶显示 24pt `checkmark.circle.fill`，未置顶显示 24pt 空心圆；圆形按钮为 24×24pt，置顶操作和无障碍标签保持有效。
- 语言名选择按钮、整行高亮、分隔线位置及长按置顶菜单未改。

## 三条门禁

1. iOS `xcodebuild` — **exit 0**（`BUILD SUCCEEDED`）
2. macOS `xcodebuild` — **exit 0**（`BUILD SUCCEEDED`）
3. `bash scripts/test-app-state.sh` — **exit 0**（全部自测通过）

`git diff --check` — **exit 0**。
