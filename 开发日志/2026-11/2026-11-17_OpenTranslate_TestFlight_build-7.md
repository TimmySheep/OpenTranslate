# OpenTranslate TestFlight iOS build 7（新图标）

- 日期：2026-11-17
- 构建：iOS 1.0.1 (7)，App Store Connect build `5b31a811-a50f-4df5-93b1-85f740198d52`
- 状态：`VALID`；已加入内部测试组「内部测试」(`8345138c-7bcb-4e6a-bc9c-20e4efd30e57`)；`usesNonExemptEncryption=false`；`autoNotifyEnabled=true`
- 分支/提交：`feature/app-settings-ui`
  - `759658a` — cherry-pick 图标提交 `2f8e547`（24 个图标文件）
  - `04157a5` — `Bump TestFlight build to 7`（pbxproj 中 8 处 `CURRENT_PROJECT_VERSION` 6→7；`MARKETING_VERSION` 保持 1.0.1）
  - 两个提交均未 push

## 图标替换范围

| 落点 | 内容 |
|---|---|
| `Assets.xcassets/AppIcon.appiconset` | 12 个 PNG（mac 16/32/128/256/512 双倍图 + iOS 1024 无 alpha） |
| `Assets.xcassets/LargeIcon.imageset/128.png` | iOS 启动页 |
| `Resources/Icon.png` | App 内 128 |
| `Shared (Extension)/Resources/icon/` | 16/32/48/96/128 |
| `extension/public/icon/` | 16/32/48/96/128 |
| `extension/src/assets/icons/opentranslate.png` | 256 RGBA（侧边栏/关于页/Toast/悬浮按钮） |

源图：1254×1254 JPEG（浅米白圆角方块 + 三条橙杠，外部近白背景 254 vs 方块 250–252）。现有生成脚本假定黑底源图，故先做源图归一化：8×8 BOX 下采样取行列亮度 profile 定 bbox `(155,158)-(1100,1100)`，方块外涂黑为 `/tmp/icon-source-A.jpg`，再跑 `generate-app-icons.py` / `generate-ext-icons.py`。

## 构建与上传

1. `scripts/build-safari.sh`（safari-mv3 + options-app）→ `scripts/sync-resources.sh`
2. GUI（Aqua）会话内归档导出，钥匙串可达：
   `xcodebuild archive -scheme "OpenTranslate (iOS)" -configuration Release -destination "generic/platform=iOS"`，自动签名 + ASC API key 认证
3. `xcodebuild -exportArchive`（`method=app-store-connect`, `destination=export`）
4. `xcrun altool --upload-app -t ios` → `UPLOAD SUCCEEDED with no errors`

## 验证证据

- 归档日志 `ARCHIVE SUCCEEDED` / `IOS_ARCH_RC=0` / `IOS_EXPORT_RC=0` / `IOS_UPLOAD_RC=0`
- 归档产物 `Info.plist` 为 `1.0.1 (7)`；`Assets.car` 4.6 MB
- `assetutil --info` 解析到 8 个 `AppIcon` rendition，1024×1024 来源为新 `universal-icon-1024@1x.png`
- IPA `9,829,260` 字节，`/tmp/ot7/ios-export/OpenTranslate.ipa`
- ASC API 回读：build 7 `processingState=VALID`，`internalBuildState=READY_FOR_BETA_TESTING`
- 构建产物图标哈希抽查：源码 / `extension/.output/safari-mv3/icon/128.png` / `Shared (Extension)/Resources/icon/128.png` 三处均为 `2b2affb458c79efe…`

## 已知项

- `Info.plist` 未包含 `ITSAppUsesNonExemptEncryption`，导出合规声明是上传后经 ASC API 补的。建议在工程里加上该键（值 `false`），否则每次上传都要手工补。
- 扩展图标 16px 已到像素极限，三条横杠在小尺寸下会糊成一点；如需可辨认需单独为 16px 画简化版。
- 签名归档必须在 GUI 登录会话执行；SSH 会话会 `errSecInternalComponent`。
- `pnpm type-check` 有两项既有错误（`vitest.setup.ts` 的 `afterEach`、`wxt.options-app.config.ts` 的 TS2554），在基线 `314ec46` 上同样复现，与本轮图标改动无关。
- `pnpm test` 1022 例中 1018 通过，4 例失败为外部网络（Google 超时、Microsoft token 404）。

## 相关

- 网站 `apps.timhuang.net` 的 `opentranslate/assets/icon.png` 已同步换成新版（1024 RGBA 透明圆角），公网逐字节回读一致；旧图备份在 `/srv/lighthouse/backups/apps-opentranslate-icon-20261117-031241/`
