# OpenTranslate TestFlight build 10（原生 SwiftUI 界面 + 新图标）

- 日期：2026-11-17
- 构建：
  - iOS 1.0.1 (10)，ASC build `dde94f82-74a6-4e99-9f2a-3f237cc63da6`
  - macOS 1.0.1 (10)，ASC build `0e311697-d7cb-41f9-9141-83705ce1bb57`
- 状态：均 `VALID`、`usesNonExemptEncryption=false`、已加入内部测试组「内部测试」、`IN_BETA_TESTING`、自动通知开
- 分支/提交：`~/Projects/ot-translate-app`，分支 `feat/translate-app`（未 push）
  - `51b561b` — 原生 SwiftUI 翻译界面 + 新图标
  - `c16263b` — Bump TestFlight build to 10

## 为什么换掉 WebView

build 9 用 WKWebView 加载 React 产物，用户验收后明确拒绝：「看起来就是网页应用」。结论：WebView 渲染的界面无法呈现苹果原生质感（滚动惯性、字体渲染、控件反馈、真玻璃均为浏览器语义），CSS 模拟的 Liquid Glass 无法替代系统材质。因此回到原生路线。

## 本次内容

### 原生界面（`Shared (App)/TranslateScreen.swift`，314 行）

- 三端自适应：iPhone 单列 / iPad 与 Mac 左右双栏（宽度阈值 + `regular` sizeClass 双重判断，避免 iPhone 横屏误触发）
- 材质分级：iOS/macOS 26+ 用 `glassEffect`（`.rect(cornerRadius:)` 与 `.circle` 两种形状），旧系统退回 `ultraThinMaterial`；**不使用 `.blur()` 自绘**
- 背景：暖色渐变 + 3 个缓慢漂移光斑（给玻璃提供可折射内容）
- 输入态：就地 `TextEditor`、自动聚焦、取消/完成、字数统计、键盘避让
- 结果页：译文大字、复制、`AVSpeechSynthesizer` 朗读、词性/音标、释义、其他译法、例句、provider 来源提示
- 设置 sheet：LLM provider 列表（标注是否已配 key）、`SecureField` 输入 key、模型名、兼容接口 URL、目标语言、外观；「完整设置 →」用 WKWebView 打开打包的 `settings/options-app.html`（唯一允许的 WebView 场景）
- 回退：`opentranslate.nativeScreen.enabled` 可切回原 WebView 路径，Storyboard 保留

### 翻译链路（原生）

- 用 `URLSession` 调 OpenAI Chat Completions 兼容接口，超时 45 秒
- 配置读 App Group `group.net.timhuang.opentranslate` 下的 `opentranslate.config.json`（`providersConfig` 数组，key 在 `apiKey`，端点是 `baseURL`，目标语言 `language.targetCode`）
- 结构化输出：提示词要求 JSON（`translation` / `partOfSpeech` / `ipa` / `alternatives` / `examples` / `definitions`），`Codable` 解析，字段缺失容错，解析失败降级为「把返回文本当纯译文」
- 支持：DeepSeek、OpenAI、SiliconFlow、Groq、DeepInfra、Mistral、Together、Cerebras、Moonshot、阿里云、火山、xAI、OpenRouter 等 Chat Completions 兼容协议
- **暂不支持**（需走完整设置/WebView）：DeepLX、Microsoft、Google Translate、Gemini、Anthropic、Azure、Bedrock、Cohere、Vercel、Replicate、Ollama
- 无 key 时不发请求，顶部显示「添加 AI 提供商后即可翻译」提示条

### 新图标

源图为效果展示图（1536×1024，黑底圆角方块 + 半透明玻璃石 + 三条白线）。处理方式：PIL 检测深色区域边界裁出左侧主图标 → iOS 1024 满幅无 alpha（圆角外填图标黑底）→ macOS 10 张按现有脚本规则（824/1024 内容 + 透明留白）→ 扩展 5 尺寸×2 处（贴边保留圆角、四角透明）→ `BrandIcon.imageset` 128px。

共 23 个输出文件。验收：1024 四角为黑色；macOS 1024 四角 alpha=0；预览拼图（浅/深背景各一行 × 6 尺寸）中每个尺寸均为单个图标、裁切正确；256/128/64 下三条白线清晰，32 勉强可辨，16 模糊（尺寸物理极限）。

## 验证证据

- 不签名 `xcodebuild`：iOS、macOS 均退出码 0
- 归档：`ARCHIVE SUCCEEDED`、`IOS_ARCH_RC=0`、`IOS_EXPORT_RC=0`、`IOS_UPLOAD_RC=0`、`MAC_ARCH_RC=0`、`MAC_EXPORT_RC=0`、`MAC_UPLOAD_RC=0`
- 图标确实进包：`assetutil` 解析 `Assets.car`，1024 rendition 由 build 9 的 773,968 字节变为 663,397 字节，`Assets.car` 由 4.68 MB 降至 4.03 MB
- ASC 回读：iOS `dde94f82…`、macOS `0e311697…` 均 `VALID`、`IN_BETA_TESTING`、`enc=false`、已在测试组

## 尚未验证 / 已知问题

- **真机翻译未验证**：构建环境没有可用 API key，未做真实请求。结构化结果的提示词效果、各家 provider 兼容性都需真机确认
- 语音与相机仍未接入（原生桥：`Speech` / `VisionKit`），界面按钮当前无实际功能
- 16px 扩展图标模糊，属尺寸极限
- `BrandIcon` 为深色图标，用在暖米色主界面上可能偏重，需视觉确认后决定是否另做浅底版本
- 未做 TestFlight 真机安装验收
