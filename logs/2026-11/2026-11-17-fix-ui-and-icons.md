# UI 与图标修复

- 影响：`apple/OpenTranslate/Shared (App)/TranslateScreen.swift` 及 App、Safari Extension 的图标资源；详细实现、完整验收输出与状态清单见 [任务报告](../../.dispatch/REPORT-fix-ui-and-icons.md)。
- UI：麦克风按钮变为语音输入占位；源/目标语言选择、配置写回及交换行为完成。
- 图标：重制 iOS、macOS、Safari Extension 和 BrandIcon 资源，未修改硬性验收脚本。
- 验证：iOS Simulator 与 macOS 不签名 Xcode 构建退出码均为 0；`verify_icons.py` 连续两次 PASS；Swift 文件 383 行。
- 无 commit/push、无 build 号变更。
