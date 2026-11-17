import Foundation

struct NativeGenerationSettings: Equatable {
    var systemPrompt: String
    var temperature: Double
    var maxTokens: Int
}

enum NativePromptDefaults {
    static let systemPrompt = "你是专业翻译助手。将用户输入翻译为{{targetLanguage}}。只返回合法 JSON，不要 Markdown 或额外文字。结构：{\"translation\":\"主译文\",\"partOfSpeech\":\"词性或空\",\"ipa\":\"音标或空\",\"alternatives\":[{\"text\":\"其他译法\",\"note\":\"使用场景\"}],\"examples\":[{\"source\":\"原句\",\"target\":\"译文\"}],\"definitions\":[\"简短释义\"]}。"
    static let placeholders = [
        "{{targetLanguage}}",
        "{{input}}",
        "{{webTitle}}",
        "{{webDescription}}",
        "{{webContent}}",
        "{{webSummary}}",
    ]
}

final class NativeGenerationStore {
    private enum Key {
        static let systemPrompt = "nativeSystemPrompt"
        static let temperature = "nativeTemperature"
        static let maxTokens = "nativeMaxTokens"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: NativeGenerationSettings {
        let storedTemperature = (defaults.object(forKey: Key.temperature) as? NSNumber)?.doubleValue ?? 0.2
        let storedMaxTokens = (defaults.object(forKey: Key.maxTokens) as? NSNumber)?.intValue ?? 0
        return NativeGenerationSettings(
            systemPrompt: defaults.string(forKey: Key.systemPrompt) ?? "",
            temperature: Self.clampedTemperature(storedTemperature),
            maxTokens: Self.clampedMaxTokens(storedMaxTokens)
        )
    }

    func setSystemPrompt(_ value: String) {
        defaults.set(value, forKey: Key.systemPrompt)
    }

    func setTemperature(_ value: Double) {
        defaults.set(Self.clampedTemperature(value), forKey: Key.temperature)
    }

    func setMaxTokens(_ value: Int) {
        defaults.set(Self.clampedMaxTokens(value), forKey: Key.maxTokens)
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: Key.systemPrompt)
        defaults.removeObject(forKey: Key.temperature)
        defaults.removeObject(forKey: Key.maxTokens)
    }

    func resolvedSystemPrompt(targetLanguage: String, input: String) -> String {
        let customPrompt = settings.systemPrompt
        guard !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NativePromptDefaults.systemPrompt
        }

        let replacements = [
            "{{targetLanguage}}": targetLanguage,
            "{{input}}": input,
            "{{webTitle}}": "",
            "{{webDescription}}": "",
            "{{webContent}}": "",
            "{{webSummary}}": "",
        ]
        return NativePromptDefaults.placeholders.reduce(customPrompt) { prompt, placeholder in
            prompt.replacingOccurrences(of: placeholder, with: replacements[placeholder] ?? "")
        }
    }

    private static func clampedTemperature(_ value: Double) -> Double {
        guard value.isFinite else { return 0.2 }
        return min(2.0, max(0.0, value))
    }

    private static func clampedMaxTokens(_ value: Int) -> Int {
        value == 0 ? 0 : min(8192, max(256, value))
    }
}
