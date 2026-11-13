# OpenTranslate 项目状态（截至 2026-11-13）

## 上架状态

| 平台 | 版本 | 状态 | 说明 |
|---|---|---|---|
| iOS | 1.0 (build 2) | **已上架** | 32 个国家/地区可下载，日本区已确认可搜到 |
| macOS | 1.0 (build 3) | **等待审核** | 2026-11-13 12:01 UTC 提交；通过后自动发布 |

已修复的坑：曾显示「已从 App Store 移除」，根因是 App Availability 从未设置任何国家/地区（审核通过 ≠ 已在售）。

## 上架三道门槛

| 门槛 | 现状 | 影响 |
|---|---|---|
| App 可用性 | ✅ 已设为「所有国家或地区」 | — |
| 欧盟 DSA 交易商身份 | ❌ 未声明（18 个欧盟国家 `TRADER_STATUS_NOT_PROVIDED`） | 欧盟 27 国不可下载 |
| 中国大陆 ICP | ✅ 有备案；当前 `contentStatuses = AVAILABLE`，未被卡 | 暂无 |

## 代码状态

- 仓库：`TimmySheep/OpenTranslate`（fork 自 `mekedron/OpenTranslate`，GPL-3.0）
- 主工作副本：MacBook Pro `~/AWS/OpenTranslate`
- 基线 tag：`pre-app-settings-20261113`（iOS 1.0 与 macOS 1.0 构建所用状态）
- 工作分支：`feature/app-settings-ui`
- 已提交：`097086c` App 与扩展共用配置（骨架），23 文件 / +1061 行

### 已完成的能力

- App Group `group.net.timhuang.opentranslate` 共享存储（`SharedSettingsStore.swift`）
- 扩展侧原生消息桥：`sharedSettings.get / set / status / markMigrated`
- 扩展写入时镜像到 App Group；启动时反向同步；冲突按 `lastModifiedAt + source` 判定
- App 内 WKWebView 设置页（目前只有「默认目标语言」一项）

### 已知债

- **API Key 明文落在 App Group**（整份 config 一起写），未拆 Keychain
- App 内设置界面只覆盖 1 项，扩展侧有 11 个页面 / 9,056 行
- 无 iCloud 同步（仅同设备共享）

## 下一步：方案 A

把扩展的完整设置界面搬进 App（一份 UI 代码，两处复用）。任务书见 `docs/TASK-app-settings-ui.md`。

## 关键决策记录

| 日期 | 决策 |
|---|---|
| 2026-11-13 | 采用方案 A（复用扩展设置界面），不采用原生 SwiftUI 重做 |
| 2026-11-13 | iCloud 不做完整版；倾向轻量版（只同步非敏感项），排在方案 A 之后 |
| 2026-11-13 | macOS 发布方式保持「审核通过后自动发布」 |
| 2026-11-13 | 执行交给 Grok Bot：一个实现 Bot、一个审查 Bot，各自独立 |
