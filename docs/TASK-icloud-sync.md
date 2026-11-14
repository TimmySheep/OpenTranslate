# 任务书：OpenTranslate 轻量 iCloud 同步（并行分支 B）

## 与并行任务的关系（先读）

同一时间还有另一个 Bot 在做「把扩展设置界面搬进 App」（任务书 `docs/TASK-app-settings-ui.md`）。
**两边并行，靠文件所有权隔离**，任何一方越界都算阻断级错误。

### 你（iCloud 任务）独占的文件

- `apple/OpenTranslate/Shared (App+Extension)/**`（含 `SharedSettingsStore.swift`，可改）
- 新增 `apple/OpenTranslate/Shared (App+Extension)/CloudSettingsSync.swift`
- `apple/OpenTranslate/*/**.entitlements`
- `apple/OpenTranslate/OpenTranslate.xcodeproj/project.pbxproj`（**只有你能改**）

### 你绝对不能碰的文件（属于任务 A）

- `extension/**`（任何文件）
- `apple/OpenTranslate/Shared (App)/Resources/**`
- `apple/OpenTranslate/Shared (App)/ViewController.swift`
- `apple/OpenTranslate/Shared (Extension)/SafariWebExtensionHandler.swift`

## 工作方式

- **独立 worktree**，不要动主工作区：
  `git -C ~/AWS/OpenTranslate worktree add ~/Projects/ot-icloud -b feat/icloud-sync feature/app-settings-ui`
- 只在 `~/Projects/ot-icloud` 里干活
- 每完成一个交付物单独 commit，不许 push、不许开 PR、不许碰 App Store Connect

## 目标

同一 Apple ID 的多台设备之间，**非敏感设置**保持一致。API Key 不同步。

### 允许同步（白名单，其余一律不同步）

- `language.sourceCode` / `language.targetCode`
- 显示模式类开关（双语对照 / 仅译文）
- 主题、字号等纯偏好项

### 绝对不同步

- 任何 provider 的 API Key、token、secret
- 队列参数、缓存
- 账号、账单、设备标识相关内容

## 实现约束

1. 用 `NSUbiquitousKeyValueStore`，**不要**引入 CloudKit。
2. **不改**现有 App Group 的 key 名与 JSON 结构。iCloud 是叠加层；读取优先级：iCloud（较新）> App Group（本机）。
3. 冲突沿用现有 `lastModifiedAt` 策略，不要新造一套。
4. 开启 iCloud capability（KVS），在报告里说明改了哪个 entitlements 与 pbxproj 的哪几行。
5. **红线**：写入 iCloud 前必须按白名单过滤。不做过滤、把整份 config 推上去，直接算失败。
6. 未登录 iCloud / KVS 不可用时，必须静默降级，行为与本机版完全一致。

## 交付物

1. `CloudSettingsSync.swift`：白名单过滤 + 读写 + 合并（纯逻辑，可单测）
2. 单元测试：白名单外字段（尤其 API Key）**不得**进入 iCloud payload
3. 与 `SharedSettingsStore` 的接入：本机写入后按白名单镜像到 iCloud；启动时按时间戳合并
4. entitlements 与 pbxproj 的 iCloud capability 配置
5. 报告：改动的文件清单 + 白名单过滤的测试输出

## 验收

- `xcodebuild -scheme "OpenTranslate (macOS)" ... MACOSX_DEPLOYMENT_TARGET=12.0 build` 成功
- `xcodebuild -scheme "OpenTranslate (iOS)" -destination "generic/platform=iOS" build` 成功
- 单测通过，且**能证明** API Key 不在 payload 里（贴出测试输出）
- 关闭 iCloud 时行为与现在一致（降级不报错）
- 你改的文件全部落在上面「独占」清单内
