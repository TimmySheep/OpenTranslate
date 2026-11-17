# OpenTranslate 功能清单（build 18）

状态约定：

- `[x]` 已完成并验过——行尾括号写依据：commit / 门禁 / ASC 状态
- `[~]` 已实现，未做运行时验收
- `[ ]` 未开始

适用提交：`cbca34a`（build 18）。验过 = 编译通过 + 自测通过，不含人眼观感。

## 主界面卡片与手势

- [x] L0 页面背景 / L1 输入主卡 / L2 语言胶囊与历史面板三层结构（c63e9c0，iOS+macOS 编译 exit 0）
- [x] 输入主卡高度 `min(420, max(260, 高度×0.55))`、圆角 28、内容最大宽 560（c63e9c0）
- [x] 语言胶囊高 44 / 圆角 12，浅色描边 `#DADCE0`（c63e9c0）
- [x] 抓手 44×4、热区 124×48，仅未编辑时生效（c63e9c0）
- [x] 拖动实时联动卡片位移与历史高度，松手 35% 阈值吸附、<6pt 视为轻点（c63e9c0）
- [x] 统一弹簧动画 `.spring(0.38, 0.82)`（c63e9c0）
- [x] 进入编辑禁用抓手并收起历史（c63e9c0）
- [x] 动作栏 86pt 麦克风严格居中、44pt 侧控件、12pt 间距（c90b044，审计尾项已核）
- [x] iOS 粘贴胶囊只在有剪贴板文字时渲染（c90b044）
- [x] iOS / macOS 共用单列布局，macOS 最小窗口 380×560（c63e9c0）
- [~] 拖动与吸附的真实手感（无 GUI 交互验收）
- [~] 深/浅色两套配色在真机上的观感（无运行时截图验收）

## 历史与收藏

- [x] 历史按 `(input, sourceCode, targetCode)` 去重，重复项前移不增总数（c63e9c0，自测 PASS）
- [x] 上限 100 条，超出淘汰最旧（c63e9c0，自测 PASS）
- [x] 每次变更原子写盘（c63e9c0）
- [x] 坏 JSON 重命名为 `history.corrupt.json`，从空历史继续（c63e9c0，自测 PASS）
- [x] 读取后按 `createdAt` 倒序（c63e9c0，自测 PASS）
- [x] 历史行点击只回填原文并收起，不自动翻译（c63e9c0）
- [x] 长按删除单条 / 清空全部均有确认框（c63e9c0）
- [x] 收藏复用 `HistoryEntry.isSaved`，不建第二份数据（b51103b）
- [x] 结果页书签切换收藏并立即持久化（b51103b，自测 PASS）
- [x] 历史面板「已保存」按 `isSaved` 筛选（b51103b）
- [x] 删除记录 / 清空历史连带清除收藏（b51103b，自测 PASS）
- [~] 历史面板展开态的滚动与截断观感（无运行时验收）
- [ ] 收藏与历史跨设备同步（无 iCloud，仅同设备）

## 结果页

- [x] 原文 + 源语言名 + 音标行（音标空则整行隐藏）（b51103b）
- [x] 译文 + 目标语言名（b51103b）
- [x] 示例卡，`examples` 为空整卡不渲染（b51103b）
- [x] 词性 / 释义 / 近义词胶囊，三者全空整卡不渲染（b51103b）
- [x] 近义词 `note` 并入胶囊无障碍标签，点击复制（b51103b）
- [x] 顶部返回保留输入、「新翻译」清空回主页（b51103b）
- [x] 历史 / 复制 / 朗读 / 删除 / 收藏接入既有动作（b51103b）
- [x] 重开历史记录只用保存字段重建，不虚构示例与词典内容（b51103b）
- [~] 与谷歌结果页的像素级观感比对（无运行时验收）
- [ ] 点赞 / 点踩（无反馈后端，刻意不做无效控件）
- [ ] 蓝色编号义项与英文长释义（数据模型无对应字段）

## 语言选择器与置顶

- [x] 置顶存 `UserDefaults` key `pinnedLanguageCodes`，兼容旧数据（b51103b，自测 PASS）
- [x] 最近置顶插头部，重复置顶不改顺序，取消即移除（b51103b，自测 PASS）
- [x] 读入时去重、剔除不支持 code 并回写（b51103b，自测 PASS）
- [x] 置顶组按存储顺序展示、参与搜索、从字母组排除（b51103b）
- [x] 左侧圆形按钮 24×24：已置顶实心勾、未置顶空心圆（527a7bc，iOS+macOS 编译 exit 0）
- [x] 检测语言显示 16pt 蓝色 sparkles 且禁用（527a7bc）
- [x] 行长按菜单提供置顶 / 取消置顶（b51103b）
- [~] 圆形按钮与整行高亮的点按观感（无运行时验收）

## 设置

- [x] 系统提示词编辑，空/纯空白回退内置默认（c90b044，自测 PASS）
- [x] 恢复默认按钮与「直译 / 意译 / 口语」预设（c90b044）
- [x] 占位符 `{{targetLanguage}}`、`{{input}}` 替换，网页类占位符替换为空（c90b044，自测 PASS）
- [x] 温度 0–2 步进 0.1，越界钳制后持久化（c90b044，自测 PASS）
- [x] 最大输出 tokens 0（不限）/ 256–8192，步进 256（c90b044，自测 PASS）
- [x] 温度与 `max_tokens` 实际写入请求体（c90b044）
- [x] 目标语言 Picker 覆盖 `TranslateModel.languages` 全量（c90b044）
- [x] 提供商 / API Key / 模型名 / 模型列表 / 自定义 Base URL（既有能力，本轮回归 exit 0）
- [x] `resetToDefaults` 清空三项并回读默认（c90b044，自测 PASS）
- [ ] `max_tokens` vs `max_completion_tokens` 逐 provider 核实
- [ ] 生成设置与 Safari 扩展双向同步（架构决策：本轮不做）
- [ ] 网页端多套提示词模板移植

## 分发

- [x] build 号 bump 到 18（cbca34a）
- [x] iOS / macOS `Info.plist` 声明 `ITSAppUsesNonExemptEncryption = false`（cbca34a）
- [x] iOS 1.0.1 (18) 归档并上传成功，2026-11-18 04:12:36 CST（ASC `processingState = VALID`）
- [x] macOS 1.0.1 (18) 归档并上传成功，2026-11-18 04:17:59 CST（ASC `processingState = VALID`）
- [x] 两包挂到「内部测试」组 `8345138c-7bcb-4e6a-bc9c-20e4efd30e57`（ASC `internalBuildState = IN_BETA_TESTING`，autoNotify 开）
- [x] 源码归档 tar.gz 生成并校验（`OpenTranslate-build18-cbca34a-20261118.tar.gz`，3.2 MB，sha256 38242681…da50）
- [~] TestFlight 真机运行时观感验收（由 Timmy 本人完成，尚未执行）
- [x] 四道门禁全绿：iOS Debug 0 / macOS Debug 0 / `test-app-state.sh` 0（34 PASS）/ `pnpm build:safari` 0（cbca34a 时点）
- [ ] 外部测试组提交
- [ ] 正式提审 1.0.1

## 已知阻塞

- **运行时观感无人验收**：无模拟器交互能力，界面点按、拖动、深浅色观感全部停在「已实现」而非「已验收」。这是 build 18 进入外部测试前的唯一硬缺口。
- **`max_tokens` 键名未逐家核实**：若某 provider 只接受 `max_completion_tokens`，该家会忽略或报错；当前统一 `max_tokens`。
- **生成设置不与 Safari 扩展同步**：App 与扩展各存一套，属有意架构决策，非缺陷，但用户会看到两处设置不一致。
- **谷歌对标功能缺口**：点赞/点踩、编号义项与长释义、离线语言包、实时对话，四项都未开始。
- **ASC API 间歇 500**：上传与查询都要重试（本轮 iOS 重试 1 次、macOS 重试 3 次成功）。
- **Safari 构建提示**：`options-app` entrypoint 被跳过、存在 >500 kB chunk，构建 exit 0 但产物未做体积优化。
