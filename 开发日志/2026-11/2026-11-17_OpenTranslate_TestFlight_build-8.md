# OpenTranslate TestFlight build 8（修复 App 内嵌设置页图标空白）

- 日期：2026-11-17
- 构建：
  - iOS 1.0.1 (8)，ASC build `3df48e1c-040a-4a7a-99ca-87941ffd781c`
  - macOS 1.0.1 (8)，ASC build `c6d93fb6-ffa6-4be3-9b23-5b5c36a215dd`
- 状态：均 `VALID`；均 `usesNonExemptEncryption=false`；均已加入内部测试组「内部测试」(`8345138c-7bcb-4e6a-bc9c-20e4efd30e57`)；`internalBuildState=IN_BETA_TESTING`；`autoNotifyEnabled=true`
- 分支/提交：`feature/app-settings-ui`（未 push）
  - `467ba67` — `fix(ui): load provider logos directly on own pages and fall back to initials`
  - `e3a2b88` — `Bump TestFlight build to 8`（pbxproj 8 处 `CURRENT_PROJECT_VERSION` 7→8）

## Bug 根因

`ProviderIcon` 对远程 http 图片走 `shouldProxyAssetUrl` → `resolveContentScriptAssetBlob` 的 background 代理路径。这套代理只为 content script 设计（注入第三方网页，受宿主页面 CSP/CORS 约束，需要 background 代取）。

但判断只白名单了扩展协议：

```ts
const EXTENSION_PROTOCOLS = new Set(["chrome-extension:", "moz-extension:", "safari-web-extension:"])
return !EXTENSION_PROTOCOLS.has(protocol)   // file:// 掉进"需要代理"
```

macOS/iOS App 用 `webView.loadFileURL(...)`（`Shared (App)/ViewController.swift:107`）加载打包的 `settings/options-app.html`，页面协议是 `file://` → 被判定为第三方页面 → 去调用在 App 内并不存在的扩展 background → `resolveContentScriptAssetBlob` 返回 null → `.catch(() => setResolvedLogo(null))` → 不渲染任何元素，只剩外层 `bg-white + border` 的空圆圈。

对照：Safari 里 options 页是 `safari-web-extension://` → 在白名单 → 直接 `<img src>` → 正常。这解释了「浏览器正常、App 空白」，与配置同步无关（用户已确认同步本身正常）。

自建/内联 provider（Tensdaq 的 `customProviderLogo`、DeepLX 的 `deeplxLogoLight/Dark`）不走远程 http 分支，所以在任何上下文都正常。

## 修复内容（3 处代码 + 2 个测试）

1. `background-asset-url.ts`：`EXTENSION_PROTOCOLS` → `OWN_PAGE_PROTOCOLS` 并纳入 `file:`；抽出具名 `isThirdPartyPage()` 让语义显式；`resolveContentScriptAssetBlob` 增加并透传 `pageUrl` 参数（原来依赖 window 默认值，属同类隐患）。
2. `provider-icon.tsx`：新增 `hasLoadError`，覆盖 bitmap 失败、canvas 取不到、`drawImage` 抛错、`<img onError>` 四条失败路径，失败时渲染**首字母圆标**（`name` 首字符大写，缺失用 `?`），复用现有 `iconContainerVariants` 尺寸。
3. 测试：`background-asset-url.test.ts` 增加 `file://` 页面断言 —— `shouldProxyAssetUrl` 为 false、`resolveContentScriptAssetBlob` 返回 null、**且不发起代理消息**（`sendMessageMock` 未被调用）；`provider-icon.test.tsx` 增加远程图 error 后渲染首字母的用例。

## 验证证据

- 指定两份测试文件：9 项全部通过
- `pnpm test` 全量：1020 通过 / 4 失败（失败为外部网络：Google 超时、Microsoft token 刷新 404，与本次改动无关）
- `pnpm build:safari`：成功
- `pnpm type-check`：仅任务书标注的两项既有错误（`vitest.setup.ts` 的 `afterEach`、`wxt.options-app.config.ts` 的 TS2554），无新增
- 归档产物核对：`OpenTranslate.app/settings/chunks/api-providers-DzLNfRDr.js` 内含 `"file:"` 协议判断；`options-app` chunk 由 build 7 的 `options-app-BRc25lMN.js` 变为 `options-app-C9bBSgz7.js`（sha256 `eb8a6bd8…`），说明修复代码确实进了 App 内嵌设置页
- iOS：`ARCHIVE SUCCEEDED` / `IOS_ARCH_RC=0` / `IOS_EXPORT_RC=0` / `IOS_UPLOAD_RC=0`
- macOS：`MAC_ARCH_RC=0` / `MAC_EXPORT_RC=0` / `MAC_UPLOAD_RC=0`

## 待人工确认

图标在 App 内的实际显示需安装 build 8 后目视确认：设置页「API 提供商」列表中的 OpenAI / DeepSeek / Gemini 应显示彩色 logo；断网时应退化为首字母圆标而非空圆圈。

## 备注

- 未采用「把 logo 打包进本地」的方案：图标属上游品牌资产，跟随 CDN 更新更合适；打包会带来发版耦合与包体膨胀。
- opencode 执行时的代理限制：gpt-6-luna 走 Codex OAuth，Pro 系统代理里的 SOCKS（`SOCKSEnable:1`）会让其 fetch 抛 `UnsupportedProxyProtocol`。可用组合：`--standalone` + `HTTPS_PROXY=http://127.0.0.1:7890`（不能用 socks5 的 `ALL_PROXY`）。
