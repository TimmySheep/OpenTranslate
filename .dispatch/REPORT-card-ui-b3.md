# REPORT card-ui-b3

## 三项生成设置：存储与读取

三项新设置只使用 App 本地 `UserDefaults.standard`，key 常量见 `apple/OpenTranslate/Shared (App)/NativeGenerationSettings.swift:22-25`；统一读取与默认值见 `:34-41`，立即写入见 `:44-54`。

| 设置 | UserDefaults key | UI 读取/写入 | 翻译请求读取点 |
|---|---|---|---|
| 系统提示词 | `nativeSystemPrompt` | 设置 sheet 打开时加载 `TranslateScreen.swift:1748-1756`；编辑、预设和恢复默认即时写入 `:1653-1657, 1789, 1793-1794` | `translate()` 读取 generation settings 并解析提示词 `TranslateScreen.swift:191-200`；文本模式作为 system message、图片模式沿用既有 user-content 结构 |
| 温度 | `nativeTemperature` | 初始值从 store 读取 `TranslateScreen.swift:1752-1755`；Slider 改动即时写入 `:1677-1693` | 请求体的 `temperature` 字段 `TranslateScreen.swift:211` |
| 最大输出 tokens | `nativeMaxTokens` | 初始值从 store 读取 `TranslateScreen.swift:1752-1755`；Stepper 改动即时写入 `:1695-1712` | 大于 0 时添加 `max_tokens`，0 时不加入字段 `TranslateScreen.swift:211-213` |

默认目标语言 Picker 使用 `TranslateModel.languages` 全量选项（`TranslateScreen.swift:116, 1640-1644`）；保存仍走原有 `config.language.targetCode` 写回路径（`TranslateScreen.swift:132-152`）。

## 提示词解析顺序

`NativeGenerationStore.resolvedSystemPrompt`（`NativeGenerationSettings.swift:62-78`）严格按以下顺序处理：

1. 对用户提示词做 `trimmingCharacters(in: .whitespacesAndNewlines)` 判空；空串或纯空白返回 `NativePromptDefaults.systemPrompt`（`NativeGenerationSettings.swift:64-66`），不会继承扩展的 `??` 空串 bug。
2. 非空时逐一替换六个占位符：`{{targetLanguage}}` 使用目标语言中文名、`{{input}}` 使用待翻译原文；四个网页占位符替换为空字符串（`:68-78`）。
3. 替换后不 trim 或做其他加工，保留用户文本原样。

内置默认提示词以 `{{targetLanguage}}` 保留原来按目标语言变化的部分；`translate()` 在默认路径把它换成当前语言名，并保留原文本/图片两种指令措辞；编辑器点“恢复默认”填入相同默认文本时也按内置默认处理（`TranslateScreen.swift:192-200`）。

## 为什么存本地，不写共享 config

遵从任务书架构决策。R1 已在 `.dispatch/settings-inventory.md:25, 320-323` 核实：共享 config 的 `providersConfig[]` 是 strict schema，未知字段可能导致扩展配置校验失败；Swift 读写也可能丢弃未知字段。将新 key 放入 App 本地 `UserDefaults` 不会触碰 App Group schema，也不依赖 App Group 权限状态。代价是三项生成设置不会同步 Safari 扩展；扩展继续使用自己的 `customPromptsConfig`。

## `max_tokens` 键名依据

本轮没有逐家核实当前各 provider 对 `max_tokens` / `max_completion_tokens` 的要求；前置调研也将其列为未确认项（`.dispatch/settings-inventory.md:338`）。因此按任务书要求，不猜测并统一用 `max_tokens`，不加未经核实的 provider 分支；值为 0 时完全省略该键。各 provider 对该字段的兼容差异仍是遗留风险。

## 未移植的网页版设置

不移植快捷键/悬停热键、划词工具栏、整页翻译范围与 DOM 批量队列、预加载/小段落过滤、译文 CSS、悬浮按钮、站点黑白名单和自动翻译规则、右键菜单、Practice/Live/字幕功能及 Google Drive 同步。这些依赖浏览器命令、页面 DOM/content script、URL/站点上下文或网页端专属服务；App 没有对应机制，照搬会成为无效开关。对应前置梳理见 `.dispatch/settings-inventory.md:307-318`。

## WEB-AUDIT 第 3 节尾项核对

- 主卡：**已满足**（`TranslateScreen.swift:310, 345-346, 474-494`：卡高、44×4 抓手、28 圆角及深浅色底）。
- 结果页：**已满足**（`TranslateScreen.swift:735-763, 850-1032`：卡片结果布局与固定语言栏）。
- 搜索框：**已满足**（`TranslateScreen.swift:1453-1454`：52 高、26 圆角）。
- 关闭 X：**已满足**（`TranslateScreen.swift:1424-1429`：44×44 含圆形底）。
- 选择器卡片：**已满足**（`TranslateScreen.swift:1385, 1520`：深色 `#1F1F21` / 浅色 `#F1F3F4`、圆角 20）。
- 选择器跟随系统明暗：**已满足**（`TranslateScreen.swift:1383-1386` 使用环境 `colorScheme` 计算颜色；picker 内没有强制 `.preferredColorScheme(.dark)`）。
- 置顶顺序：**已满足**（`TranslateScreen.swift:1397-1399, 1590-1595` 保持 `pinnedCodes` 顺序；`LanguagePinStore.swift:41-55` 新置顶插入首位并持久化）。
- 历史与收藏数据层：**已满足**（`TranslationHistoryStore.swift:4-16, 59-73`；UI 收藏分段筛选见 `TranslateScreen.swift:1149-1150`）。
- 粘贴胶囊：本轮调整（`TranslateScreen.swift:656-667`），左侧、30 高 Capsule、深浅色指定底色；无剪贴板内容时整个按钮条件不渲染。
- 底部动作栏：本轮调整（`TranslateScreen.swift:650-688`），侧控件 44、语音 86、两侧间隔 12，语音 x 坐标取几何中心。
- 语言栏常驻与位置：本轮将输入态动作栏/语言栏移出 ScrollView（`TranslateScreen.swift:317-368`）；结果态语言栏见 `:735-763`。两态均采用同一 `languageBar`（`:622-628`）、最大宽度 560、水平边距 24、底部边距 12。
- 主页品牌标题与设置入口仍保持有意差异；未顺手改动，符合审计原文“保留品牌与常驻齿轮”的说明（`.dispatch/card-ui-ref/WEB-AUDIT.md:162-165`）。

## 四门禁结果

1. iOS：`cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (iOS)' -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_DEBUG_DYLIB=NO` — exit 0。
2. macOS：`cd apple && xcodebuild -project OpenTranslate/OpenTranslate.xcodeproj -scheme 'OpenTranslate (macOS)' -destination 'generic/platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` — exit 0。
3. 状态自测：`bash scripts/test-app-state.sh` — exit 0，所有逐条检查 PASS。
4. 扩展：`cd extension && pnpm build:safari` — exit 0。输出包含既有非阻断 warning：`options-app` entrypoint skipped、部分 minified chunks 超 500 kB。

## 变异检验

- 红：将空值回退分支改为原样返回空串，脚本 exit 1；第 2 条空白/换行用例 FAIL。
- 绿：恢复正确回退后，脚本 exit 0；新增状态用例全部 PASS。
