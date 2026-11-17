# OpenTranslate TestFlight build 9（App 打开即翻译）

- 日期：2026-11-17
- 构建：
  - iOS 1.0.1 (9)，ASC build `3709456e-9465-432c-b1c1-0452bb0203a7`
  - macOS 1.0.1 (9)，ASC build `499b67b5-9cf7-4ff0-adde-dd9873cbeacd`
- 状态：均 `VALID`、`usesNonExemptEncryption=false`、已加入内部测试组「内部测试」、`IN_BETA_TESTING`、自动通知开
- 工作树/分支：`~/Projects/ot-translate-app`，分支 `feat/translate-app`（未 push）
- 提交：`bbb0840`（接入 translate-app 为 App 入口）、`7a68001`（Bump build to 9）

## 本次变化

App 启动页从「设置页」换成「翻译界面」：

- `ViewController.swift` 优先加载 `settings/translate-app/translate-app.html`，`options-app.html` 保留为 fallback
- `scripts/sync-resources.sh` 现在同时同步 options-app 与 translate-app 两套产物（两套必须一起同步，否则 `rsync --delete` 会互相删掉）
- `settings` 在 Xcode 工程里是 folder reference，因此新增子目录无需改 pbxproj

翻译界面能力（第一版）：主界面（Google 骨架 + CSS 玻璃 + 暖色漂移光斑）、输入态（自动聚焦、字数统计）、结果页（译文/词性/音标/其他译法/例句，zod 校验 AI 结构化 JSON，缺字段整块隐藏、畸形降级为纯译文）、设置 sheet（提供商/目标语言/外观/完整设置入口）、语言选择器（可搜索 + 常用分组 + 语言代码）、深色模式、复制与朗读。

## 关键技术结论

- **CORS 不需要代理**：`file://` 页面在 WKWebView 中可直连 API。DeepSeek 默认配置即返回 401；OpenAI 需 `allowUniversalAccessFromFileURLs=true`，而宿主 App 早已设置（`ViewController.swift:54-56`）。因此翻译层直接用 `fetch`，未引入 `WKURLSchemeHandler`。
- **`file://` 下 `<script type="module">` 会被拦**（页面不启动），构建需打成单 chunk 内联/非 module 形式，已在 translate-app 构建配置中处理。
- 浮层（下拉、sheet）背景不透明度需 ≥0.94，否则背后文字透上来与面板内容重叠。

## 验证证据

- `pnpm build:safari` 退出码 0（12.05 MB）；translate-app 独立产物 3.53 MB
- 无签名 `xcodebuild`（iOS Debug）退出码 0，bundle 内含 `settings/translate-app/translate-app.html`、chunks、assets、_locales、icon
- `pnpm test`：1020 通过 / 4 失败（既有外部网络：Google 超时、Microsoft 404），无新增失败
- 归档产物核对：iOS 与 macOS 的 App 包内均有 `settings/translate-app/translate-app.html`
- ASC 回读：iOS `3709456e…`、macOS `499b67b5…` 均 `VALID`、`IN_BETA_TESTING`、`enc=false`、已在测试组

## 尚未验证（重要）

- **真实翻译未跑通**：没有使用任何真实 API key，AI 结构化结果的格式与提示词效果都还没在真机上验证
- **语音 / 相机是占位**：WKWebView 内拿不到系统听写与 Vision OCR，点击只提示「将在 App 内启用」
- **App Group 配置读取的端到端表现**：Web 侧通过 `sharedSettings` handler 读配置，harness 无法覆盖，需真机确认能否读到用户已存的 key
- 未做 TestFlight 真机安装验收

## 后续待办

1. 真机装 build 9，确认打开即翻译、首启提示正确、填 key 后能真翻译
2. 若 App Group 读取失败，需在 Xcode 工程侧补 handler 或调整读取顺序
3. 语音与相机需要原生桥（Speech / VisionKit）
4. 视觉上仍可打磨：语言下拉面板宽度与输入卡不对齐（右侧露边）、浅色模式玻璃感受 CSS 模拟限制
