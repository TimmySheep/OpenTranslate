# Translate App step 1

- Date: 2026-11-17
- Worktree: `/Users/TimmySheep/Projects/ot-translate-app`, branch `feat/translate-app`, based on `14f7be5`.
- Added a standalone translate-app entrypoint and WXT build configuration. Translation dispatches through the existing direct provider path; no background messaging or new dependency was added.
- CORS probe used only the fake key `sk-invalid-test`: DeepSeek returned HTTP 401 in both WKWebView configurations. OpenAI returned `TypeError: Load failed` in default configuration and HTTP 401 with universal file access enabled; default cause remains undetermined. Existing App source already enables universal file access.
- Validation: pre-change and post-change `pnpm build:safari` succeeded. Standalone App build succeeded. WKWebView `loadFileURL()` rendered the app controls with the existing universal-access setting. Full suite: 1020 passed, 4 existing external-network failures (Google timeouts, Microsoft 404). Translation itself was not verified; no real API key was read or used. Type check still reports two errors in untouched files (`vitest.setup.ts` and `wxt.options-app.config.ts`).
- Detailed reports: `.dispatch/REPORT-cors-probe.md` and `.dispatch/REPORT-translate-app.md`.

- No Xcode project changes, commit, or push.

## 2026-11-17 — 原生 SwiftUI 主界面第一步

- 在 `apple/OpenTranslate/Shared (App)/TranslateScreen.swift` 新增 SwiftUI 主界面及 Preview，并更新 Xcode 工程引用；`ViewController.swift` 默认用 hosting controller 承载原生界面，同时保留 Storyboard/WKWebView 回退（UserDefaults 键 `opentranslate.nativeScreen.enabled=false`）。
- Liquid Glass 使用 `.otGlass(cornerRadius:)` 分级：iOS/macOS 26+ `.glassEffect`，旧系统 `.ultraThinMaterial`，未用 `.blur()`；包含三个动态暖色光斑以及宽屏双栏布局。
- 验证：任务要求的 iOS 与 macOS 不签名 `xcodebuild` 均 BUILD SUCCEEDED，退出码 0；部署目标未改。未运行模拟器/视觉验收；无翻译逻辑。未调用 CUA、签名、archive、上传、改 build 号、加依赖、改 `extension/`、commit 或 push。
- 详细报告：`.dispatch/REPORT-native-step1.md`。

## 2026-11-17 — Translate App first complete feature pass

- Expanded the existing translate-app UI, settings, shared config writes, structured AI result parsing, replaceable provider fetch transport, and error/timeout feedback. No dependencies added.
- Validation: `pnpm build:safari` succeeded (12.04 MB); standalone translate-app build succeeded (3.53 MB). `pnpm test`: 1020 passed, 4 known external-network failures (Google timeouts, Microsoft token endpoint 404). Targeted ESLint has no errors (two array-key warnings); full type-check remains blocked by existing `vitest.setup.ts` and `wxt.options-app.config.ts` errors.
- Reused `/tmp/ot-cors-probe/load-app --universal` only to load the final `file://` app. DOM output confirmed React rendered the home controls and first-run banner; no API/CORS probe was run. No usable API key environment variable was present and no real key was used; **翻译链路未做真机验证，仅有类型与构建验证**.
- Speech and camera remain explicit placeholders with user-facing toasts. No Xcode project changes, CUA, commit, or push.
- Full evidence and limitations: `.dispatch/REPORT-translate-app-full.md`.

## 2026-11-17 — Translate App visual polish

- Updated only `extension/src/entrypoints/translate-app/main.tsx` and `style.css`: icon/banner polish, inline monochrome SVG action icons, visible drifting warm glows and consistent glass surfaces, warm-brown translate action, balanced action row, and searchable/grouped language pickers. Kept no-key settings/highlight and editor cancel/complete/count logic unchanged.
- Validation: Safari extension build succeeded (12.05 MB); standalone translate-app build succeeded (`extension/.output/translate-app-final`, 3.53 MB). Full tests: 1020 passed, 4 existing external-network failures. Targeted ESLint: 0 errors, 2 existing index-key warnings. Type-check remains blocked by existing `vitest.setup.ts` and `wxt.options-app.config.ts` errors.
- Existing `file://` loader rendered the main controls and no-key banner; the two custom language triggers render as buttons, so native select count is now zero. Did not run CORS probes, CUA, Xcode, commit, or push. Details: `.dispatch/REPORT-translate-app-polish.md`.

## 2026-11-17 — Translate App 浮层不透明度修复

- 仅修改 `extension/src/entrypoints/translate-app/style.css`：语言 popover、设置 sheet 使用浅/深色 `.96` 不透明度专用背景，blur 从 24px 降至 12px，搜索框背景提至 `.96`；保留内描边高光与布局，未改变普通内容卡片。
- 验证：`pnpm build:safari` 成功（12.05 MB）；独立 translate-app 构建成功（`extension/.output/translate-app-final/`，构建总大小 3.53 MB）；已检查最终 CSS 包含预期颜色与模糊值。未作浏览器截图视觉验证。
- 未新增依赖、调用 CUA、运行 CORS 探针、改 Xcode 工程、commit 或 push。详细记录：`.dispatch/REPORT-translate-app-translucency.md`。

## 2026-11-17 — App integration

- Updated `scripts/sync-resources.sh` to separately sync options-app and translate-app into the settings folder and its `translate-app/` child, keeping both `rsync --delete` targets isolated. Updated `ViewController.swift` to prefer translate-app, retain options-app fallback, and grant file access to the `settings` root.
- Validation: Safari build, options-app standalone build, and translate-app standalone build all succeeded. Sync listing confirmed both apps and their resources. Unsigned iOS `xcodebuild` succeeded (exit 0); built `OpenTranslate.app/settings/translate-app/` contains the HTML, JS chunk, CSS, locale files, icons, manifest, and assets. `pnpm test`: 1020 passed; 4 known external-network failures (Google timeouts, Microsoft 404).
- No build number change, archive/export/upload, dependency addition, UI/business logic change, CUA, commit, push, or cleanup. Full evidence: `.dispatch/REPORT-app-integration.md`.

## 2026-11-17 — 原生 SwiftUI 主界面缺陷修复

- 修复顶部栏品牌图标为 `BrandIcon` imageset；圆形玻璃按钮改用 `.otGlassCircle()`，避免对圆角矩形玻璃做事后圆形裁剪。
- 顺手让 iPhone 竖屏输入卡扩展填充可用高度，并要求 iOS 双栏同时满足宽度阈值及 regular horizontal size class；保留 3 个柔和漂移光斑、Storyboards 和原 WKWebView 回退。
- 验证：不签名 iOS 与 macOS `xcodebuild` 均 BUILD SUCCEEDED，退出码 0；部署目标保持 iOS 15.0 / macOS 12.0。未使用 `.blur()`，未运行模拟器/视觉验收。
- 未调用 CUA、签名、archive、上传、改 build 号、加依赖、触碰 `extension/`、删除 WebView 路径、commit 或 push。报告：`.dispatch/REPORT-native-step1-fix.md`。

## 2026-11-17 — 原生翻译功能第二步

- 在 `apple/OpenTranslate/Shared (App)/TranslateScreen.swift` 完成原生编辑态、URLSession Chat Completions 翻译、结构化 JSON 容错、结果交互和 BYOK 设置 sheet；仅此文件是本轮新增/修改的 Swift 文件。App Group 配置按 `SharedSettingsStore` 的 config JSON 结构读写，key 不打印或写日志。保留完整设置 WKWebView 入口和原生界面回退开关。
- 原生兼容 provider：DeepSeek、OpenAI、SiliconFlow、OpenAI-compatible、Groq、DeepInfra、Mistral、Together.ai、Cerebras、Moonshot AI、Alibaba Cloud、Volcengine、xAI、OpenRouter。DeepLX、Microsoft/Google 翻译等非 Chat Completions provider 暂不支持，详见任务报告。
- 不签名 iOS Simulator 与 macOS `xcodebuild` 均退出码 0；`git diff --check` 通过；文件行数见报告。App Group 当前无可见 config，环境无匹配 API key，因此未做真机翻译验证。
- 未改 build 号或部署目标；未调用 CUA、commit、push、archive 或上传。报告：`.dispatch/REPORT-native-step2.md`。


## 2026-11-17 — 深色玻璃版图标替换

- 按 `.dispatch/TASK-icon-B.md` 从 `icon-source-B.jpg` 主图裁切生成 iOS、macOS、Safari 扩展和 BrandIcon 资源；macOS/扩展遵循项目现有脚本尺寸与留白/圆角规则。未触碰本工作区其他已有改动。
- 验证：23 个 PNG 文件的尺寸、模式和字节数记录于 `.dispatch/REPORT-icon-B.md`；iOS 1024 四角为 RGB 黑色、无 alpha；macOS 1024 四角 alpha 均为 0；预览 `.dispatch/icon-B-preview.png` 已生成。BrandIcon 暖米色背景建议后续提供浅底版本，未改配色。
- 未改 build 号、未 commit/push、未调用 CUA。
