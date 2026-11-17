# iOS 编辑框回车完成、语言置顶与上传菜单

- 影响文件：`apple/OpenTranslate/Shared (App)/TranslateScreen.swift`（唯一改动文件，+91 / -22 行）。
- 编辑模式：删除 iOS 输入区的「取消 / 完成」按钮行，改为 `ReturnCommitTextEditor`（`UIViewRepresentable` 包 `UITextView`，`returnKeyType = .done`）在按下 Return 时收起键盘并调用 `commitEditing()`，与旧「完成」行为一致；顶部保留「按 Enter 完成」提示，粘贴多行文本仍保留换行。macOS 卡片未改（用户只要求 iOS）。
- 语言置顶：原 `swipeActions` 写在 `ScrollView` 里的卡片上，`swipeActions` 只对 `List` 生效，所以实际无法置顶/取消置顶。改为每行右侧显式置顶按钮（`pin` / `pin.slash`，已置顶黄色，36×44pt 热区，VoiceOver 朗读「置顶 <语言>」），点按不关闭语言面板；整行点按仍是选择语言。空置顶时隐藏「已置顶的语言」标题。
- 上传弹窗：`confirmationDialog` 改为锚在「上传」按钮上的 `Menu`（`menuIndicator(.hidden)`，Menu 自身约束为 44×44，外层居中），弹出位置跟随按钮；菜单项仍是「从照片选择 / 选择文档」。
- 验证：`xcodebuild -scheme "OpenTranslate (iOS)"`（generic iOS Simulator，`CODE_SIGNING_ALLOWED=NO`）与 `OpenTranslate (macOS)` 均 `BUILD SUCCEEDED`；在 ASC-iPhone16Pro（iOS 27.2）安装启动并截图，主界面布局与上传/语音/相机按钮位置未变。
- 限制：模拟器没有点按注入工具，Enter 提交、置顶按钮、菜单锚定三项交互只做了编译与代码层确认，未在设备上实际点击验证。
- 未 commit、未 push（`feat/translate-app` 无上游分支）、未改 build 号、未新增依赖。
