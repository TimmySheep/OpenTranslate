# Translate App step 1

- Date: 2026-11-17
- Worktree: `/Users/TimmySheep/Projects/ot-translate-app`, branch `feat/translate-app`, based on `14f7be5`.
- Added a standalone translate-app entrypoint and WXT build configuration. Translation dispatches through the existing direct provider path; no background messaging or new dependency was added.
- CORS probe used only the fake key `sk-invalid-test`: DeepSeek returned HTTP 401 in both WKWebView configurations. OpenAI returned `TypeError: Load failed` in default configuration and HTTP 401 with universal file access enabled; default cause remains undetermined. Existing App source already enables universal file access.
- Validation: pre-change and post-change `pnpm build:safari` succeeded. Standalone App build succeeded. WKWebView `loadFileURL()` rendered the app controls with the existing universal-access setting. Full suite: 1020 passed, 4 existing external-network failures (Google timeouts, Microsoft 404). Translation itself was not verified; no real API key was read or used. Type check still reports two errors in untouched files (`vitest.setup.ts` and `wxt.options-app.config.ts`).
- Detailed reports: `.dispatch/REPORT-cors-probe.md` and `.dispatch/REPORT-translate-app.md`.
- No Xcode project changes, commit, or push.

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
