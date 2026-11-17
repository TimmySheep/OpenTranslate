# 任务书：审查 OpenTranslate「App 内完整设置界面」（方案 A）

## 角色与边界（先读这段）

你是**独立审查方**，不是实现方。实现由另一个 Bot 完成。

- **只在实现方报告完成后才开始审查**，不要提前审半成品。
- **只读源码**。你唯一可以写的文件是 `reports/review-<日期>.md`。
- **不改任何源码、不 commit、不 push、不开 PR**。
- **不要用自己的偏好加戏**：验收基准是实现任务书的章节号，不是你觉得应该怎么做。

## 审查对象

- 仓库：`~/Projects/ot-app-settings`（实现方的 worktree），分支 `feat/app-settings-ui-v2`
- 实现任务书：`docs/TASK-app-settings-ui.md`
- 基线：`pre-app-settings-20261113`（iOS 1.0 / macOS 1.0 构建所用状态）

## 必须逐项核对的「死线」（实现方越界即打回）

1. `extension/src/utils/atoms/storage-adapter.ts` 的**默认实现行为**是否被改变
2. `extension/src/types/config/config.ts` 的 schema 是否有任何字段变动
3. `_locales/**` 文案是否被编辑（只允许复制）
4. App Group 协议：`SharedSettingsStore.swift` 的 key 名与 JSON 结构、`SafariWebExtensionHandler.swift` 的消息名（`sharedSettings.get/set/status/markMigrated`）是否变化
5. 翻译核心（provider、队列、content script）是否被动过逻辑
6. `Shared (App)/ViewController.swift` 现有消息桥是否保持向后兼容

## 必须验证机制，不接受自述

实现方如果声称「App 里改完立刻生效」「扩展能感知变更」，**必须看代码确认走的是哪条路径**（例如 `grep -rn "sharedSettings" apple/ extension/src/utils/safari-shared-settings/`），并确认 `watch` 推送真的接上了，而不是「重新打开 App 才刷新」。

## 回归证据要求

实现方必须提供、你要复核的实测值：

- `pnpm build:safari` 成功
- `xcodebuild -scheme "OpenTranslate (iOS)"` 与 `"OpenTranslate (macOS)"`（后者带 `MACOSX_DEPLOYMENT_TARGET=12.0`）均成功
- `pnpm test` 通过，含 `safari-shared-settings/__tests__/sync.test.ts`
- 扩展仍能翻译网页（不是「应该能」，要有实际执行记录）

## 输出格式

`reports/review-<日期>.md`，包含：

1. 结论行：**可合并** / **有条件通过** / **阻断**
2. 阻断项清单（有则列，无则写「阻断项：无」）
3. 死线六项逐项核对结果
4. 回归证据复核结果（你自己跑的命令 + 实测输出）
5. 发现但不算阻断的问题（另列，不要混进阻断项）

## 纪律

- 发现实现方自报与实际不符，**直接写进阻断项**，不要替它圆场。
- 不要扩大到方案 A 之外的需求；发现别的问题写成建议，不算阻断。
- 卡住超过 20 分钟说清卡在哪，不要猜着审。
