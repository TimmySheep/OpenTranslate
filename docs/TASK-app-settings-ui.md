# 任务书：把扩展的完整设置界面搬进 App（方案 A）

## 一句话目标

App（iOS + macOS）打开后显示**与 Safari 扩展完全一致的设置界面**（现有 11 个页面），在 App 里改完，扩展立即生效。**一份 UI 代码，两处复用**，以后扩展新增设置，App 自动就有。

## 死线：以下区域绝对不许改（现阶段功能是好的）

1. `extension/src/utils/atoms/storage-adapter.ts` —— **默认实现保持原样**。只能把接口抽出来允许注入另一种实现，不能改 WXT storage 的行为。
2. `extension/src/types/config/config.ts` —— config schema 一个字段都不许动。
3. `_locales/**` —— 文案内容不许改（可以复制，不许编辑）。
4. App Group 协议 —— `SharedSettingsStore.swift` 里的 key 名、JSON 结构，`SafariWebExtensionHandler.swift` 里的消息名（`sharedSettings.get/set/status/markMigrated`），一律不变。已发布版本用着它，改了就会分裂。
5. 翻译核心 —— `provider/`、队列、content script、background 的翻译路径，不许改逻辑。
6. `Shared (App)/ViewController.swift` 现有的消息桥行为必须保持向后兼容。

## 交付物（按顺序，每步可独立验收）

1. **存储适配层可注入**：把 `storageAdapter` 改成工厂/接口形式，默认仍返回 WXT 实现（行为零变化），另提供 `createBridgeAdapter()` 走 WKWebView 消息桥。
2. **App 侧 entrypoint**：新增 WXT entrypoint（建议名 `options-app`），复用 `entrypoints/options` 的页面组件，产物输出到独立目录。
3. **构建接线**：构建脚本把产物同步到 `apple/OpenTranslate/Shared (App)/Resources/settings/`，并加入 Xcode 工程资源。
4. **原生桥增强**：支持整份 config 的读取/写入，以及配置变更向 WKWebView 的 `watch` 推送（App 改动后界面同步刷新）。
5. **i18n 静态打包**：`_locales` 随 App 资源一起打包，提供不依赖 `browser.i18n` 的读取实现。
6. **能力门控**：6 处 `sendMessage`（`setTranslateBatchQueueConfig`、`setTranslateRequestQueueConfig`、`clearAllTranslationRelatedCache` 等）和 1 处 `browser.runtime.getURL("/translation-hub.html")` 链接，在 App 内**隐藏**。
7. **双端可运行**：iOS 与 macOS 打开 App 都能看到完整设置并读写成功。

## 验收标准（缺一不可）

- `cd extension && pnpm build:safari` 成功
- `xcodebuild -scheme "OpenTranslate (macOS)" ... MACOSX_DEPLOYMENT_TARGET=12.0 build` 成功
- `xcodebuild -scheme "OpenTranslate (iOS)" -destination "generic/platform=iOS" build` 成功
- `pnpm test` 通过（含 `safari-shared-settings/__tests__/sync.test.ts`）
- 运行验证：App 内把目标语言从 A 改成 B，扩展侧读到的也是 B；反向亦然
- **回归**：扩展仍能正常翻译网页（用 yle.fi 或任意外语页验证）

## 工作方式

- 在**独立 worktree** 干活，不要动 `~/AWS/OpenTranslate` 主工作区：
  `git worktree add ~/Projects/ot-app-settings -b feat/app-settings-ui-v2 feature/app-settings-ui`
- 每完成一个交付物就 commit（窄范围，一次一件事），不要攒一大堆
- 不许 `git push`，不许开 PR，不许碰 App Store Connect
- 卡住超过 30 分钟没有进展，就在回复里说明卡在哪、需要什么，不要硬试

## 参考

- `docs/SHARED-SETTINGS.md`（已有的共享设置协议说明）
- `docs/SAFARI.md`（构建与调试手册）

## 阶段二：轻量 iCloud 同步（**等方案 A 验收通过后才开始，不要提前做**）

目标：同一个 Apple ID 的多台设备之间，**非敏感设置**保持一致。API Key 不同步。

### 允许同步的字段（白名单，其余一律不同步）

- `language.sourceCode` / `language.targetCode`
- 显示模式类开关（双语对照 / 仅译文）
- 主题、字号等纯偏好项

### 绝对不同步

- 任何 provider 的 API Key、token、secret
- 队列参数、缓存
- 任何与账号、账单、设备标识相关的内容

### 实现约束

1. 用 `NSUbiquitousKeyValueStore`（最简单、够用），不要引入 CloudKit。
2. **不改**现有 App Group 的 key 名与 JSON 结构；iCloud 是**叠加**的一层，读优先级：iCloud（较新）> App Group（本机）。
3. 冲突仍按 `lastModifiedAt` 判定，沿用现有策略，不要新造一套。
4. 需要开启 iCloud capability（KVS），并在任务报告里说明改了哪个 entitlements。
5. **必须在写入前过滤白名单**：不做过滤、直接把整份 config 推上去，是这次任务的红线错误。

### 验收

- 白名单内的字段改动后能同步；白名单外（尤其 API Key）**在 iCloud 里查不到**
- 未登录 iCloud / iCloud 不可用时，App 行为与现在完全一致（降级，不报错）
- App Group 原有同步路径不受影响

