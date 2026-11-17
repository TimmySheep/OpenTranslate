import Foundation

final class LanguagePinStore {
    private(set) var pinned: [String]

    private let defaults: UserDefaults
    private let key: String
    private let validCodes: Set<String>

    private static let defaultPinned = ["cmn", "cht", "eng", "jpn", "kor"]
    private static let supportedCodes: Set<String> = [
        "cmn", "cht", "eng", "jpn", "kor", "fra", "deu", "spa", "rus", "ita", "por", "ara", "hin", "ben", "urd",
        "ind", "msa", "tha", "vie", "tur", "nld", "swe", "nor", "dan", "fin", "pol", "ukr", "ces", "ell", "heb",
        "fas", "tam", "tel", "mar", "guj", "pan", "swa", "ron", "hun", "bul", "hrv", "srp", "slk", "slv", "cat",
        "eus", "glg", "isl", "gle", "cym", "est", "lav", "lit", "khm", "lao", "mya", "nep", "sin", "amh", "yor",
        "zul", "afr", "kaz", "uzb", "mon", "yid"
    ]

    init(
        defaults: UserDefaults = .standard,
        key: String = "pinnedLanguageCodes",
        validCodes: Set<String>? = nil
    ) {
        self.defaults = defaults
        self.key = key
        self.validCodes = validCodes ?? Self.supportedCodes

        let storedCodes = defaults.stringArray(forKey: key)
        let initialCodes = storedCodes ?? Self.defaultPinned
        pinned = Self.uniqueValidCodes(initialCodes, validCodes: self.validCodes)

        if let storedCodes, storedCodes != pinned {
            defaults.set(pinned, forKey: key)
        }
    }

    func isPinned(_ code: String) -> Bool {
        pinned.contains(code)
    }

    func toggle(_ code: String) {
        guard validCodes.contains(code) else { return }
        if isPinned(code) {
            unpin(code)
        } else {
            pinned.insert(code, at: 0)
            persist()
        }
    }

    func pin(_ code: String) {
        guard validCodes.contains(code), !isPinned(code) else { return }
        pinned.insert(code, at: 0)
        persist()
    }

    func unpin(_ code: String) {
        let originalCount = pinned.count
        pinned.removeAll { $0 == code }
        if pinned.count != originalCount {
            persist()
        }
    }

    private func persist() {
        defaults.set(pinned, forKey: key)
    }

    private static func uniqueValidCodes(_ codes: [String], validCodes: Set<String>) -> [String] {
        var seen = Set<String>()
        return codes.filter { validCodes.contains($0) && seen.insert($0).inserted }
    }
}
