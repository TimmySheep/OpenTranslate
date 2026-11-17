# 批次 1 实现报告

## 视觉层级与 modifier

- **L0 页面背景**：`pageBackground.ignoresSafeArea()`；深色 `#131314`、浅色 `#FFFFFF`。
- **L1 输入主卡**：高度 `min(420, max(260, 可用高度 × 0.55))`，卡内容最大宽 560 并居中；输入区水平 padding 24、顶部 24、底部 48。`background(cardBackground, in: RoundedRectangle(cornerRadius: 28))` 并 `clipShape`；深色无阴影，浅色 `black.opacity(0.08), radius: 24, x: 0, y: 8`。输入卡容器最大宽 608。
- **抓手**：`RoundedRectangle(cornerRadius: 2)`，44×4；深色 `white.opacity(0.24)`、浅色 `black.opacity(0.16)`，距卡底 10。
- **L2 语言胶囊**：`RoundedRectangle(cornerRadius: 12)`，高 44；深色 `#2B2C2E`，浅色 `#F1F3F4` 加 1pt `#DADCE0` 描边。语言栏最大宽 560。
- **L2 历史面板**：深色 `#1B1C1E`、浅色 `#F8F9FA`，圆角 20；高度上限 `min(320, 可用高度 × 0.42)`。列表原文 15pt 单行、译文 13pt 最多两行、相对时间 11pt。
- **动作栏**：语音按钮直径 86，深色填充 `#A8C7FA`、浅色 `#1A73E8`，图标 34pt；图标深色主题用 `#131314`、浅色主题白色。相机/文件入口是无底色 44×44 按钮，22pt 图标，无图标下方文字。

## 拖动与历史规则

- 抓手热区只在未编辑时叠加：124×48pt，以抓手为中心（水平各 40pt、垂直各 24pt），并向下偏移 14pt 对齐抓手；卡片其他区域仍由输入区点击进入编辑。
- `DragGesture(minimumDistance: 0)` 实时更新卡片位移和历史高度，范围 0 至 `min(320, 可用高度 × 0.42)`。松手按 `predictedEndTranslation.height` 吸附：投影高度超过最大值 35% 展开，否则收起；横向主导的拖动回到起始高度。小于 6pt 的轻点切换展开/收起。
- 动画统一 `.spring(response: 0.38, dampingFraction: 0.82)`；编辑态禁用抓手手势，进入编辑会收起历史。
- 历史以 `(input, sourceCode, targetCode)` 去重；重复记录删除旧项并以新译文插入最前，不增加总数。最多 100 条，超出淘汰最旧项；每次变更原子写盘。读取后按 `createdAt` 倒序；坏 JSON 保留为 `history.corrupt.json`（若重名则递增后缀），从空历史继续。
- 历史行点击只回填原文并收起面板，不自动翻译；长按删除与清空全部均有确认对话框。

## iOS / macOS 差异

- 两端共用单列 `VStack` 与主卡、语言栏、动作栏；macOS 最小窗口 380×560。
- 键盘：macOS `⌘⇧H` 切换历史、`Esc` 退出编辑、`⌘V` 将剪贴板文字放入卡片；iOS 保留剪贴板胶囊。编辑器的提交操作沿用各平台键盘交互。
- 图片/文档入口：iOS 上传按钮可选文件，菜单可拍照（显示现有提示）、从照片选择或选文件；macOS 菜单从文件选择图片或 PDF。

## 验证与限制

- iOS `xcodebuild`：exit 0；macOS `xcodebuild`：exit 0；`bash scripts/test-app-state.sh`：exit 0（12 项）；`pnpm build:safari`：exit 0。
- 变异检验：把插入最前改成追加末尾时，两项顺序/淘汰测试 FAIL，exit 1；恢复后 12 项全 PASS，exit 0。
- Safari 构建提示跳过 `options-app` 且有大于 500 kB 的 chunk 警告，构建仍成功。没有进行运行中界面的实际拖动与点按验收。
- 为满足 Xcode 27 的显式模块可见性，数据层显式导入 `Combine`；状态层仍可由命令行脚本编译并通过自测。
