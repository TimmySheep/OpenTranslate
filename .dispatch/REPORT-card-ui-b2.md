# card-ui-b2 实现报告

## 结果页区块与数据映射

| 区块 | 数据来源与行为 | 空数据处理 |
|---|---|---|
| 顶部原文 | `model.input`；源语言名由 `model.sourceCode` 映射；`model.result?.ipa` 显示音标/转写 | `ipa` 为空或纯空白时隐藏整行 |
| 顶部译文 | `model.result?.translation`；目标语言名由 `model.targetCode` 映射 | 译文按当前结果显示 |
| 示例卡 | `model.result?.examples`；每项 `source` 为例句、`target` 为译文 | `examples` 为空时整卡不渲染；单项 `target` 为空时仅隐藏该项译文 |
| 翻译卡 | `partOfSpeech` 显示词性；`definitions` 显示释义；`alternatives[].text` 显示近义词胶囊 | `partOfSpeech`、`definitions`、`alternatives` 都没有有效内容时整卡不渲染 |
| 近义词辅助信息 | `alternatives[].note` 并入胶囊的无障碍标签；点击胶囊复制 `text` 并复用现有提示 | 数据没有近义词时不显示近义词组 |
| 顶部/底部操作 | 返回保留输入；“新翻译”清空输入并回主页；历史、复制、朗读、删除和收藏均接入现有状态/动作 | 无对应历史记录时收藏和删除动作禁用 |

数据模型中的 `alternatives` 是平铺数组，无法可靠关联到单独义项，因此以共享“近义词”组呈现。没有目标罗马字专用字段，不根据 `ipa` 推断或展示目标罗马字。重开历史记录只用保存的原文、译文、语言和提供商字段重建精简结果，示例及词典详情保持缺省，不生成虚构内容。

## 收藏数据流

收藏状态保存在同一条 `HistoryEntry.isSaved` 中，不建立第二份收藏数据。结果页书签按钮调用 `TranslationHistoryStore.setSaved(id:saved:)`，按当前记录 ID 更新并立即持久化；历史面板“已保存”只筛选 `isSaved == true` 的条目，并沿用历史记录按 `createdAt` 倒序的顺序。删除单条或清空历史会一并移除其收藏状态。

## 语言置顶

- 存储：`UserDefaults` 字符串数组，默认 suite 为 `.standard`，key 为现有 `pinnedLanguageCodes`，保留旧安装数据兼容。
- 顺序：数组头部是最近置顶项。首次置顶插入头部；重复置顶不重复、不改变原顺序；取消置顶移除该 code。每次实际变化立即写回。
- 读入：按原顺序去重、忽略不支持的语言 code，并将清理后的数组写回原 key。没有已有 key 时使用内置默认置顶项。
- 界面：置顶组按存储顺序展示并参与搜索过滤；置顶语言从建议和字母分组排除；取消置顶后回到字母组。左侧图标切换置顶，行的 context menu 提供对应操作，选择语言仍由行主体完成。

## 刻意不实现的 Google 元素

- 点赞/点踩：没有反馈后端，不放置无效控件。
- 蓝色编号圆圈及英文长释义：数据模型没有这类内容，不伪造。
- 头像：不展示。
- “高级”入口/区块：不加入结果详情页。

## 验证与未完成项

四项门禁及两处置顶变异检验的命令、结果和退出码见 [DONE-card-ui-b2.md](DONE-card-ui-b2.md)。没有进行运行时 GUI 点按验收；Safari 构建成功，但仍有 `options-app` 跳过和大 chunk 警告。
