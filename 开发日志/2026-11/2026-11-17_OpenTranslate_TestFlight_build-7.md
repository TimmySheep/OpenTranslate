# OpenTranslate TestFlight build 7（新图标，iOS + macOS）

- 日期：2026-11-17
- 构建：
  - iOS 1.0.1 (7)，ASC build `5b31a811-a50f-4df5-93b1-85f740198d52`
  - macOS 1.0.1 (7)，ASC build `b6c58894-14d0-4d73-8508-b27dff867fff`
- 状态：两者均 `VALID`；均加入内部测试组「内部测试」(`8345138c-7bcb-4e6a-bc9c-20e4efd30e57`)；`usesNonExemptEncryption=false`；`autoNotifyEnabled=true`；macOS `internalBuildState=IN_BETA_TESTING`
- 分支/提交：`feature/app-settings-ui`（均未 push）
  - `759658a` — cherry-pick 图标提交 `2f8e547`（24 个图标文件）
  - `04157a5` — `Bump TestFlight build to 7`（pbxproj 中 8 处 `CURRENT_PROJECT_VERSION` 6→7；`MARKETING_VERSION` 保持 1.0.1）
  - `77d4c1f` — site 落地页 favicon / og:image 图标（`site/assets/icon-128.png`、`icon-512.png`）
  - `fb00c93` — `fix(macos): declare LSApplicationCategoryType required for App Store upload`
  - 日志本身单独一条提交

## 图标替换范围（全平台）

| 落点 | 内容 | 影响 |
|---|---|---|
| `Assets.xcassets/AppIcon.appiconset` | 12 个 PNG（mac 10 张：16/32/128/256/512 双倍；iOS 1024 无 alpha） | iOS + macOS 应用图标 |
| `Assets.xcassets/LargeIcon.imageset/128.png` | 128 | iOS 启动页 |
| `Resources/Icon.png` | 128 | App 内图标；macOS 包内同名文件 18,039 字节 |
| `Shared (Extension)/Resources/icon/` | 16/32/48/96/128 | Safari 扩展（两端） |
| `extension/public/icon/` | 16/32/48/96/128 | 扩展源 |
| `extension/src/assets/icons/opentranslate.png` | 256 RGBA | 侧边栏 / 关于页 / Toast / 悬浮按钮 |
| `site/assets/icon-128.png`、`icon-512.png` | 128 / 512 RGBA | 落地页 favicon、页头 logo、og:image / twitter:image |
| `apps.timhuang.net` 的 `opentranslate/assets/icon.png` | 1024 RGBA | 展厅卡片、介绍页（异地部署，见文末） |

源图：1254×1254 JPEG（浅米白圆角方块 + 三条橙杠，外部近白背景 254 vs 方块 250–252）。现有生成脚本假定黑底源图，故先做源图归一化：8×8 BOX 下采样取行列亮度 profile 定 bbox `(155,158)-(1100,1100)`，方块外涂黑为 `/tmp/icon-source-A.jpg`，再跑 `generate-app-icons.py` / `generate-ext-icons.py`。站点与落地页的 1024/512/128 用同一 bbox + 0.24 圆角比例生成透明圆角 PNG。

## 构建与上传

1. `scripts/build-safari.sh`（safari-mv3 + options-app）→ `scripts/sync-resources.sh`
2. GUI（Aqua）会话内归档导出，登录钥匙串可达：
   - iOS：`-scheme "OpenTranslate (iOS)" -destination "generic/platform=iOS"`
   - macOS：`-scheme "OpenTranslate (macOS)" -destination "generic/platform=macOS"`
   - 自动签名 + ASC API key 认证（`-allowProvisioningUpdates -authenticationKeyPath …`）
3. `xcodebuild -exportArchive`（`method=app-store-connect`, `destination=export`）
4. `xcrun altool --upload-app`：iOS `-t ios` 传 IPA，macOS `-t macos` 传 PKG

## 验证证据

- iOS：`ARCHIVE SUCCEEDED` / `IOS_ARCH_RC=0` / `IOS_EXPORT_RC=0` / `IOS_UPLOAD_RC=0`；`Info.plist` = 1.0.1 (7)；IPA 9,829,260 字节
- macOS：`MAC_ARCH_RC=0` / `MAC_EXPORT_RC=0` / `MAC_UPLOAD_RC=0`；`Info.plist` = 1.0.1 (7)；PKG 6,472,916 字节
- `assetutil` 解析：iOS `Assets.car` 8 个 AppIcon rendition（1024 来自新 `universal-icon-1024@1x.png`）；macOS `Assets.car` 11 个 AppIcon rendition（16→1024 全部为 `mac-icon-*` 新图），`AppIcon.icns` 72,740 字节
- 图标哈希抽查：源码 / `extension/.output/safari-mv3/icon/128.png` / `Shared (Extension)/Resources/icon/128.png` 三处一致（`2b2affb4…`）
- ASC API 回读：iOS build 7 `VALID`、`READY_FOR_BETA_TESTING`；macOS build 7 `VALID`、`IN_BETA_TESTING`；两者 `usesNonExemptEncryption=false` 且已在内部测试组

## 遇到的问题与修复

- **macOS 首次上传被拒（90242）**：`The Info.plist must contain a LSApplicationCategoryType key`。工程里从未设过该键。按 ASC 登记的 App 分类（Utilities）补 `public.app-category.utilities` 到 `macOS (App)/Info.plist`，重新归档后上传通过。
- **ASC 内部测试组 `hasAccessToAllBuilds=false`**：新 build 不会自动进组，必须显式 `POST /v1/betaGroups/{id}/relationships/builds`，否则测试员看不到。
- **`builds?filter[platform]=MAC_OS` 返回 400**：改用 `include=preReleaseVersion` 取 platform；但该 include 又不能用于 `betaGroups/{id}/builds`（400），组内查询要去掉 include。

## 已知项

- `Info.plist` 仍缺 `ITSAppUsesNonExemptEncryption`，加密合规声明是每次上传后经 ASC API 补的。建议把该键（值 `false`）写进 iOS 与 macOS 的 Info.plist，否则每次发版都要手工补。
- 扩展图标 16px 已到像素极限，三条横杠在该尺寸会糊成一点；如需可辨认需单独为 16px 画简化版。
- 签名归档必须在 GUI 登录会话执行；SSH 会话会 `errSecInternalComponent`。
- 图标变更要真正到达用户，必须在 App Store 侧新建 1.0.1 版本记录并提交审核（当前线上 iOS/macOS 均为 1.0 `READY_FOR_SALE`）。仅上传 TestFlight build 不会改变已上架版本的图标。
- `site/` 的图标要对外可见需 push 到 GitHub 并由 `.github/workflows/deploy-pages.yml` 部署（上游 Pages：`https://mekedron.github.io/OpenTranslate/`）。
- `pnpm type-check` 两项既有错误（`vitest.setup.ts` 的 `afterEach`、`wxt.options-app.config.ts` 的 TS2554）在基线 `314ec46` 同样复现，与本轮改动无关；`pnpm test` 1022 例中 4 例失败为外部网络（Google 超时、Microsoft token 404）。

## 相关：apps.timhuang.net

`opentranslate/assets/icon.png` 已换成新版 1024 RGBA 透明圆角，公网逐字节回读一致；旧图备份在 tcvps `/srv/lighthouse/backups/apps-opentranslate-icon-20261117-031241/`。
