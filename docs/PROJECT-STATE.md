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

## 2026-11-18 卡片 UI 与设置开放

- 原生 App 设置新增可编辑系统提示词、温度和最大输出 tokens；三项均用 App 本地 `UserDefaults` 即时持久化，实际进入翻译请求。默认目标语言 Picker 扩展到 `TranslateModel.languages` 全量语言。
- Safari 选择器搜索框、关闭按钮和卡片样式按审计规格核对；粘贴胶囊移入动作栏，麦克风尺寸/居中与语言栏常驻位置完成调整。
- 当前 build 号占位：**build 18**（本轮未更改 Xcode build setting、未制作 TestFlight 包）。
- 遗留债：三项生成设置不与 Safari 扩展同步；provider 对 `max_tokens` / `max_completion_tokens` 的差异尚未逐一核实，本轮按要求统一使用 `max_tokens`；App 仍只提供单一系统提示词编辑，不移植网页端多模板及浏览器专属设置。

## 2026-11-18 build 18 收尾：主卡三层、结果详情页与生成设置

> 说明：上一小节（「卡片 UI 与设置开放」）记录时的状态是「build 18 占位、未制作 TestFlight 包」。本节记录该状态之后的实际出包结果，不修改上文。

### 本轮提交范围

`c63e9c0` → `cbca34a`（6 个提交，均在 `feat/translate-app`，已推 `TimmySheep/OpenTranslate`）：

| 提交 | 内容 | 规模 |
|---|---|---|
| `c63e9c0` | 主卡三层（页面背景 / 输入主卡 / 语言胶囊与历史面板）与拖动历史面板；新增 `TranslationHistoryStore.swift` | 9 文件 / +703 −106 |
| `9a29a99` | 移除越界开发日志 | — |
| `b51103b` | 结果详情页按谷歌版式重做 + 收藏 + 语言置顶；新增 `LanguagePinStore.swift` | 8 文件 / +920 −142 |
| `c90b044` | 系统提示词、温度、最大输出 tokens；新增 `NativeGenerationSettings.swift` | 9 文件 / +496 −83 |
| `527a7bc` | 语言选择器左侧圆形置顶按钮 | 3 文件 / +28 −11 |
| `cbca34a` | build 18 号 bump + `ITSAppUsesNonExemptEncryption = false` | 3 文件 / +12 −8 |

### 已完成并核对的能力

- **主卡三层**：L0 深色 `#131314` / 浅色 `#FFFFFF` 背景；L1 输入主卡高 `min(420, max(260, 可用高度 × 0.55))`、圆角 28、内容最大宽 560；L2 语言胶囊圆角 12 / 高 44（深 `#2B2C2E`、浅 `#F1F3F4` + `#DADCE0` 描边），历史面板圆角 20、上限 `min(320, 可用高度 × 0.42)`。
- **抓手与拖动**：抓手 44×4、距卡底 10；热区 124×48；拖动实时联动卡片位移与历史高度；松手按 `predictedEndTranslation.height` 吸附，投影超过最大值 35% 展开，低于 6pt 视为轻点切换；动画统一 `.spring(response: 0.38, dampingFraction: 0.82)`；编辑态禁用抓手并收起历史。
- **历史数据层**：按 `(input, sourceCode, targetCode)` 去重、重复项移到最前、上限 100 条、每次变更原子写盘、坏 JSON 重命名为 `history.corrupt.json` 后从空历史继续；历史行点击只回填原文不自动翻译，长按删除与清空均有确认。
- **结果详情页**：原文 + 源语言名 + 音标、译文 + 目标语言名、示例卡、词性/释义/近义词胶囊；某一区块无有效数据时整卡不渲染；顶部返回保留输入，「新翻译」清空回主页；历史、复制、朗读、删除、收藏接入既有状态。
- **收藏**：复用同一条 `HistoryEntry.isSaved`，不建第二份收藏数据；结果页书签调用 `TranslationHistoryStore.setSaved(id:saved:)` 立即持久化；历史面板「已保存」只筛 `isSaved == true`；删除记录一并清除收藏。
- **语言置顶**：`UserDefaults` key `pinnedLanguageCodes`（沿用旧安装数据），头部为最近置顶；重复置顶不改变顺序；非法 code 读入时剔除并回写；置顶组参与搜索并从字母分组排除；左侧按钮 24×24——已置顶 `checkmark.circle.fill`、未置顶空心圆、检测语言为 16pt 蓝色 sparkles 且禁用；行长按菜单提供同一操作。
- **生成设置**：系统提示词（含 `{{targetLanguage}}` 等占位符替换、恢复默认、直译/意译/口语预设）、温度 0–2 步进 0.1、最大输出 tokens（0 表示不限，256–8192，步进 256）；三项均写 App 本地 `UserDefaults`，温度与 `max_tokens` 实际进入请求体；默认目标语言 Picker 扩到 `TranslateModel.languages` 全量。
- **iOS / macOS 统一**：两端共用单列 `VStack` 与主卡、语言栏、动作栏；macOS 最小窗口 380×560，`⌘⇧H` 切历史、`Esc` 退出编辑、`⌘V` 取剪贴板。

### 门禁（本轮实测，全部 exit 0）

| 门禁 | 结果 |
|---|---|
| iOS Debug `xcodebuild` | exit 0，`BUILD SUCCEEDED` |
| macOS Debug `xcodebuild` | exit 0，`BUILD SUCCEEDED` |
| `bash scripts/test-app-state.sh` | exit 0，34 条 PASS |
| `cd extension && pnpm build:safari` | exit 0（仍有 `options-app` 跳过与 >500 kB chunk 提示，非阻断） |

变异检验两处：历史插入顺序（改追加末尾 → FAIL → 恢复 PASS）、提示词空值回退（改返回空串 → FAIL → 恢复 PASS）。

### build 18 与 TestFlight 内测状态

| 平台 | 版本 | 上传时间（北京时间） | processingState | 内测状态 |
|---|---|---|---|---|
| iOS | 1.0.1 (18) | 2026-11-18 04:12:36 | `VALID` | `IN_BETA_TESTING`，autoNotify 开 |
| macOS | 1.0.1 (18) | 2026-11-18 04:17:59 | `VALID` | `IN_BETA_TESTING`，autoNotify 开 |

- 两包都已挂到「内部测试」组（`8345138c-7bcb-4e6a-bc9c-20e4efd30e57`，`isInternalGroup = true`）。
- 外部测试状态为 `READY_FOR_BETA_SUBMISSION`（未提交外部测试）。
- 加密合规：`ITSAppUsesNonExemptEncryption = false`，ASC 侧 `usesNonExemptEncryption = false`。
- 上传过程：首次 export 两平台均遇 ASC `500 / Error Downloading App Information`（04:07:25）；iOS 第 1 次重试成功，macOS 第 1、2 次重试均 `rc=70`（同为 500），第 3 次成功。
- 源码归档：`~/AWS/OpenTranslate-archives/OpenTranslate-build18-cbca34a-20261118.tar.gz`，3.2 MB，sha256 `38242681bb23537a4d341341a59b7399a7d1d5fe4e1501a4fed33a0ddd03da50`。

### 已知债（build 18 之后仍存在）

1. **页面观感未做运行时验收**：本轮只有编译、自测与构建级验证，没有模拟器/真机点按与拖动；观感验收由 Timmy 通过 TestFlight 完成。
2. **`max_tokens` 键名未逐家 provider 核实**：OpenAI 系新模型可能要求 `max_completion_tokens`，当前统一用 `max_tokens`。
3. **生成设置不与 Safari 扩展同步**（架构决策）：三项参数只落 App 本地 `UserDefaults`，扩展侧有自己的一套。
4. **谷歌有而我们没有**：点赞/点踩（无反馈后端，故不放无效控件）、蓝色编号义项与长释义（数据模型没有）、离线语言包、实时对话。
5. App 内仍是单一系统提示词，不移植网页端多模板与浏览器专属设置。
6. ASC API 间歇性 500，查询与上传都需重试。
