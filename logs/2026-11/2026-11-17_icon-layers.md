# 图标图层补完

- 影响：`apple/OpenTranslate/Shared (App)/AppIcon.icon/icon.json`；按任务书接入透明前景图层，并以 `fill.solid` 指定底色。`Foreground.png` 验证为透明背景、图形边界约占 80%；未引用的 `Background.png` 保留。
- 验证：iOS/macOS 独立 actool 均退出码 0；iOS `AppIcon60x60@2x.png` PIL stddev `[58.8812, 59.3701, 60.4218]`，extrema `((6, 255), (6, 255), (7, 255))`；assetutil 中 AppIcon 的 Dark/Light/Tintable IconImageStack 均 `LayerCount=2`。
- 不签名 iOS/macOS xcodebuild 均退出码 0；两个 `.app` 均含 `Assets.car`，`CFBundleIconName=AppIcon`。完整命令输出和验收详情见 [任务报告](../../.dispatch/REPORT-icon-and-models.md#图标图层补完)。
- 未触碰模型列表、未改 build 号、未 commit/push。
