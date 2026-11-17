import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() {
        print("PASS — \(name)")
    } else {
        print("FAIL — \(name)")
        failures += 1
    }
}

private func entry(_ input: String, _ translation: String, at time: TimeInterval) -> HistoryEntry {
    HistoryEntry(
        id: UUID(),
        input: input,
        translation: translation,
        sourceCode: "eng",
        targetCode: "cmn",
        providerName: "Test Provider",
        createdAt: Date(timeIntervalSince1970: time),
        isSaved: false
    )
}

@main
private enum AppStateSelfTest {
    static func main() throws {
        guard let rootPath = ProcessInfo.processInfo.environment["APP_STATE_TEST_DIR"] else {
            fputs("FAIL — missing APP_STATE_TEST_DIR\n", stderr)
            exit(2)
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)

        let orderStore = TranslationHistoryStore(fileURL: root.appendingPathComponent("order.json"))
        orderStore.record(input: "旧记录", translation: "old", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        orderStore.record(input: "新记录", translation: "new", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        check(orderStore.entries.map(\.input) == ["新记录", "旧记录"], "新增记录插在最前")

        let duplicateStore = TranslationHistoryStore(fileURL: root.appendingPathComponent("duplicate.json"))
        duplicateStore.record(input: "same", translation: "first", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        let firstID = duplicateStore.entries.first?.id
        duplicateStore.record(input: "same", translation: "latest", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        check(duplicateStore.entries.count == 1 && duplicateStore.entries.first?.translation == "latest", "重复输入更新译文且总数不增")
        check(duplicateStore.entries.first?.id != firstID, "重复输入替换为新记录")

        let limitStore = TranslationHistoryStore(fileURL: root.appendingPathComponent("limit.json"))
        for index in 0...TranslationHistoryStore.maxEntries {
            limitStore.record(input: "item-\(index)", translation: "译文-\(index)", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        }
        check(limitStore.entries.count == TranslationHistoryStore.maxEntries, "超过 100 条时保持上限")
        check(limitStore.entries.first?.input == "item-100" && limitStore.entries.last?.input == "item-1", "超过上限时淘汰最旧记录")

        if let idToDelete = limitStore.entries.first?.id {
            limitStore.delete(id: idToDelete)
            check(limitStore.entries.count == 99 && !limitStore.entries.contains(where: { $0.id == idToDelete }), "按 ID 删除记录")
        } else {
            check(false, "按 ID 删除记录")
        }
        limitStore.clear()
        check(limitStore.entries.isEmpty, "清空全部记录")

        let persistenceURL = root.appendingPathComponent("restart.json")
        let beforeRestart = TranslationHistoryStore(fileURL: persistenceURL)
        beforeRestart.record(input: "restart", translation: "重启后读回", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        let afterRestart = TranslationHistoryStore(fileURL: persistenceURL)
        check(afterRestart.entries == beforeRestart.entries, "重启后读回一致")

        let sortURL = root.appendingPathComponent("sort.json")
        let unsorted = [entry("新", "new", at: 20), entry("旧", "old", at: 10)]
        try JSONEncoder().encode(unsorted).write(to: sortURL, options: .atomic)
        let sortedStore = TranslationHistoryStore(fileURL: sortURL)
        check(sortedStore.entries.map(\.input) == ["新", "旧"], "读入后按创建时间倒序")

        let corruptURL = root.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: corruptURL, options: .atomic)
        let corruptStore = TranslationHistoryStore(fileURL: corruptURL)
        check(corruptStore.entries.isEmpty, "坏文件不崩溃且从空历史启动")
        check(!FileManager.default.fileExists(atPath: corruptURL.path), "坏文件改名而非删除")
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.corrupt.json").path), "坏文件保留为 history.corrupt.json")

        let savedURL = root.appendingPathComponent("saved.json")
        let savedStore = TranslationHistoryStore(fileURL: savedURL)
        let savedID = savedStore.record(input: "saved", translation: "已收藏译文", sourceCode: "eng", targetCode: "cmn", providerName: "Test")
        savedStore.setSaved(id: savedID, saved: true)
        check(savedStore.entries.first?.isSaved == true, "收藏状态写入对应历史记录")
        let savedAfterRestart = TranslationHistoryStore(fileURL: savedURL)
        check(savedAfterRestart.entries.first?.isSaved == true, "收藏状态重启后读回")
        savedAfterRestart.delete(id: savedID)
        check(savedAfterRestart.entries.filter(\.isSaved).isEmpty, "删除记录后收藏状态随记录消失")

        let pinDefaultsName = "OpenTranslateAppStateSelfTest-\(UUID().uuidString)"
        let pinDefaults = UserDefaults(suiteName: pinDefaultsName)!
        let pinKey = "pinnedLanguageCodes"
        let validLanguageCodes: Set<String> = ["eng", "jpn", "fra"]

        pinDefaults.set([String](), forKey: pinKey)
        let pinStore = LanguagePinStore(defaults: pinDefaults, key: pinKey, validCodes: validLanguageCodes)
        pinStore.pin("eng")
        pinStore.pin("jpn")
        check(pinStore.pinned == ["jpn", "eng"], "置顶顺序为后置顶在前")

        pinStore.pin("eng")
        check(pinStore.pinned == ["jpn", "eng"], "重复置顶不增加条目且不改变顺序")

        pinStore.unpin("jpn")
        check(!pinStore.isPinned("jpn") && !pinStore.pinned.contains("jpn"), "取消置顶后从置顶列表消失")

        pinStore.pin("fra")
        let pinStoreAfterRestart = LanguagePinStore(defaults: pinDefaults, key: pinKey, validCodes: validLanguageCodes)
        check(pinStoreAfterRestart.pinned == ["fra", "eng"], "置顶状态与顺序重启后读回")

        pinDefaults.set(["jpn", "eng", "jpn", "unknown"], forKey: pinKey)
        let migratedPinStore = LanguagePinStore(defaults: pinDefaults, key: pinKey, validCodes: validLanguageCodes)
        check(migratedPinStore.pinned == ["jpn", "eng"], "兼容旧 key 并保序去重、忽略未知语言")
        check(pinDefaults.stringArray(forKey: pinKey) == ["jpn", "eng"], "迁移后将清理结果写回旧 key")

        pinDefaults.set([String](), forKey: pinKey)
        let emptyPinStore = LanguagePinStore(defaults: pinDefaults, key: pinKey, validCodes: validLanguageCodes)
        check(emptyPinStore.pinned.isEmpty, "空置顶状态保持为空")
        pinDefaults.removePersistentDomain(forName: pinDefaultsName)

        let generationDefaultsName = "OpenTranslateGenerationSettingsSelfTest-\(UUID().uuidString)"
        let generationDefaults = UserDefaults(suiteName: generationDefaultsName)!
        let generationStore = NativeGenerationStore(defaults: generationDefaults)
        check(
            generationStore.settings.systemPrompt.isEmpty
                && generationStore.resolvedSystemPrompt(targetLanguage: "简体中文", input: "原文") == NativePromptDefaults.systemPrompt,
            "默认空提示词回退到内置默认"
        )

        generationStore.setSystemPrompt(" \n\t ")
        check(
            generationStore.resolvedSystemPrompt(targetLanguage: "简体中文", input: "原文") == NativePromptDefaults.systemPrompt,
            "仅空白与换行提示词回退到内置默认"
        )

        generationStore.setSystemPrompt("to={{targetLanguage}} input={{input}} title={{webTitle}} desc={{webDescription}} content={{webContent}} summary={{webSummary}}")
        check(
            generationStore.resolvedSystemPrompt(targetLanguage: "简体中文", input: "Hello")
                == "to=简体中文 input=Hello title= desc= content= summary=",
            "自定义提示词替换目标语言、原文并清空网页占位符"
        )

        generationStore.setSystemPrompt("自定义\n提示词  ")
        check(
            generationStore.resolvedSystemPrompt(targetLanguage: "简体中文", input: "原文") == "自定义\n提示词  ",
            "不含占位符的自定义提示词原样返回"
        )

        generationStore.setTemperature(-1)
        check(generationStore.settings.temperature == 0, "温度下限夹取为 0")
        generationStore.setTemperature(5)
        check(generationStore.settings.temperature == 2, "温度上限夹取为 2")
        generationStore.setTemperature(0.35)
        check(generationStore.settings.temperature == 0.35, "温度范围内保留原值")

        generationStore.setMaxTokens(100)
        check(generationStore.settings.maxTokens == 256, "最大输出 tokens 下限夹取为 256")
        generationStore.setMaxTokens(99999)
        check(generationStore.settings.maxTokens == 8192, "最大输出 tokens 上限夹取为 8192")
        generationStore.setMaxTokens(0)
        check(generationStore.settings.maxTokens == 0, "最大输出 tokens 的 0 保持不限")

        generationStore.setSystemPrompt("持久化提示词")
        generationStore.setTemperature(0.7)
        generationStore.setMaxTokens(2048)
        let generationStoreAfterRestart = NativeGenerationStore(defaults: generationDefaults)
        check(
            generationStoreAfterRestart.settings == NativeGenerationSettings(systemPrompt: "持久化提示词", temperature: 0.7, maxTokens: 2048),
            "新建 store 后提示词与生成参数持久化读回一致"
        )

        generationStoreAfterRestart.resetToDefaults()
        check(
            generationStoreAfterRestart.settings == NativeGenerationSettings(systemPrompt: "", temperature: 0.2, maxTokens: 0)
                && generationStoreAfterRestart.resolvedSystemPrompt(targetLanguage: "简体中文", input: "原文") == NativePromptDefaults.systemPrompt,
            "resetToDefaults 后恢复默认"
        )
        generationDefaults.removePersistentDomain(forName: generationDefaultsName)

        if failures > 0 {
            print("\(failures) self-test(s) failed")
            exit(1)
        }
        print("All app-state self-tests passed")
    }
}
