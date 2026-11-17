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

        if failures > 0 {
            print("\(failures) self-test(s) failed")
            exit(1)
        }
        print("All app-state self-tests passed")
    }
}
