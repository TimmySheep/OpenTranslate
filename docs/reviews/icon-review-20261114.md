# 图标分支只读审查（2026-11-14）

## 结论：通过

审查基线：`feature/app-settings-ui`（`a4358a2`）。审查分支：`feat/icon-app`（包含 `0f5039b`、`1e1df82`、`9aa6e01`）及 `feat/icon-ext`（`b3dffa5`）。未切换分支；通过 `git show` 读取分支提交对象并与基线比较，未修改分支文件。

| 项目 | `feat/icon-app` | `feat/icon-ext` |
|---|---|---|
| iOS universal 图标 | `universal-icon-1024@1x.png` 为 1024×1024，PNG 模式 RGB（无 alpha 通道）；四角像素分别为 `(167,166,166)`、`(169,170,174)`、`(158,159,164)`、`(161,156,165)`，均为不透明、非黑色，画面满幅。 | 分支没有改该应用图标；本项仅审查 `feat/icon-app` 的交付内容。 |
| macOS 图标 | 十个 `mac-icon-{16,32,128,256,512}@{1x,2x}.png` 文件齐全，像素尺寸与倍率相符：16/32、32/64、128/256、256/512、512/1024。各图四个角的 alpha 均为 0，圆角以外透明。 | 分支没有改该应用图标；本项仅审查 `feat/icon-app` 的交付内容。 |
| 两个 128 图标 | `Assets.xcassets/LargeIcon.imageset/128.png` 与 `Resources/Icon.png` 均为 128×128。 | 未修改这两项；本项仅审查 `feat/icon-app` 的交付内容。 |
| 变更范围 | 相对基线只变更上述 PNG 与 `tools/icons/generate-app-icons.py`；没有 Swift、TS、pbxproj、`Contents.json` 或 entitlements 变更。 | 相对基线只新增扩展图标 PNG 与 `tools/icons/generate-ext-icons.py`；没有 Swift、TS、pbxproj、`Contents.json` 或 entitlements 变更。 |
| 扩展图标 | 未包含第二目录中的扩展图标资源。 | `extension/public/icon/` 与 `apple/OpenTranslate/Shared (Extension)/Resources/icon/` 下 `16.png`、`32.png`、`48.png`、`96.png`、`128.png` 均齐全，尺寸分别为 16×16、32×32、48×48、96×96、128×128；同名文件 SHA-256 完全相同（逐字节一致）。 |

## 证据

- `git diff --name-only feature/app-settings-ui...feat/icon-app` 列出 13 个 PNG 和 `tools/icons/generate-app-icons.py`；排除 `tools/icons/` 与 `.png` 后无输出。
- `git diff --name-only feature/app-settings-ui...feat/icon-ext` 列出 10 个 PNG 和 `tools/icons/generate-ext-icons.py`；排除 `tools/icons/` 与 `.png` 后无输出。
- 对两个分支的图像均从对应 Git 提交对象读取并检查 PNG 解码尺寸、色彩模式、角点 alpha/RGB；扩展图标逐对比较 SHA-256。

本审查为静态文件审查，未运行构建或模拟器验收。
