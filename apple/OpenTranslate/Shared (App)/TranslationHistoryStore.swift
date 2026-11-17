import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let input: String
    let translation: String
    let sourceCode: String
    let targetCode: String
    let providerName: String
    let createdAt: Date
    var isSaved: Bool
}

final class TranslationHistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    static let maxEntries = 100

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("OpenTranslate", isDirectory: true)
                .appendingPathComponent("history.json")
        }
        load()
    }

    @discardableResult
    func record(input: String, translation: String, sourceCode: String, targetCode: String, providerName: String) -> UUID {
        let entry = HistoryEntry(
            id: UUID(),
            input: input,
            translation: translation,
            sourceCode: sourceCode,
            targetCode: targetCode,
            providerName: providerName,
            createdAt: Date(),
            isSaved: false
        )

        entries.removeAll {
            $0.input == input && $0.sourceCode == sourceCode && $0.targetCode == targetCode
        }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeSubrange(Self.maxEntries..<entries.count)
        }
        persist()
        return entry.id
    }

    func setSaved(id: UUID, saved: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isSaved = saved
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return }

        do {
            let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
            let sorted = decoded.sorted { $0.createdAt > $1.createdAt }
            entries = Array(sorted.prefix(Self.maxEntries))
            if entries.count != decoded.count {
                persist()
            }
        } catch {
            preserveCorruptFile()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Keep the in-memory history usable if storage is temporarily unavailable.
        }
    }

    private func preserveCorruptFile() {
        let directory = fileURL.deletingLastPathComponent()
        let firstCandidate = directory.appendingPathComponent("history.corrupt.json")
        var destination = firstCandidate
        var suffix = 1

        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("history.corrupt.\(suffix).json")
            suffix += 1
        }

        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
