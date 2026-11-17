import SwiftUI
import AVFoundation
import WebKit
import Combine
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import PhotosUI
#elseif os(macOS)
import AppKit
#endif

let nativeScreenDefaultsKey = "opentranslate.nativeScreen.enabled"
private let nativeThemeKey = "opentranslate.app.theme"
private let nativeSchemaVersion = 80

private enum OTColor {
    static let background = Color(red: 19/255, green: 19/255, blue: 20/255)
    static let panel = Color(red: 31/255, green: 31/255, blue: 33/255)
    static let search = Color(red: 50/255, green: 50/255, blue: 51/255)
    static let blue = Color(red: 29/255, green: 73/255, blue: 115/255)
    static let mic = Color(red: 174/255, green: 198/255, blue: 245/255)
    static let selected = Color(red: 0, green: 74/255, blue: 119/255)
    static let yellow = Color(red: 1, green: 214/255, blue: 0)
    static let primary = Color(red: 232/255, green: 234/255, blue: 237/255)
    static let secondary = Color(red: 154/255, green: 160/255, blue: 166/255)
    static let separator = Color(red: 42/255, green: 43/255, blue: 45/255)
}

private struct TranslationAlternative: Codable, Identifiable {
    var text: String
    var note: String?
    var id: String { text + (note ?? "") }
}
private struct TranslationExample: Codable, Identifiable {
    var source: String
    var target: String
    var id: String { source + target }
}
private struct TranslationPayload: Codable {
    var translation: String?
    var partOfSpeech: String?
    var ipa: String?
    var alternatives: [TranslationAlternative]?
    var examples: [TranslationExample]?
    var definitions: [String]?
}
private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
    let choices: [Choice]
}

private enum ModelDirectory {
    static func requestURL(baseURL: String) -> URL? {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: normalized + "/models")
    }

    static func parse(_ data: Data) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data)
        let values: [Any]
        if let object = json as? [String: Any], let entries = object["data"] as? [Any] {
            values = entries
        } else if let entries = json as? [Any] {
            values = entries
        } else {
            throw NSError(domain: "ModelDirectory", code: 0, userInfo: [NSLocalizedDescriptionKey: "模型列表响应格式无效。"])
        }
        return Array(Set(values.compactMap { ($0 as? [String: Any])?["id"] as? String }.filter { !$0.isEmpty })).sorted()
    }

    static func cacheKey(baseURL: String, apiKey: String) -> String {
        "opentranslate.models.\(baseURL).\(String(apiKey.prefix(8)))"
    }
}

private struct NativeProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let defaultModel: String
    static let all: [NativeProvider] = [
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini"),
        .init(id: "siliconflow", name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1", defaultModel: "Qwen/Qwen3-Next-80B-A3B-Instruct"),
        .init(id: "openai-compatible", name: "OpenAI 兼容", baseURL: "https://api.example.com/v1", defaultModel: ""),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", defaultModel: "llama-3.1-8b-instant"),
        .init(id: "deepinfra", name: "DeepInfra", baseURL: "https://api.deepinfra.com/v1", defaultModel: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"),
        .init(id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai/v1", defaultModel: "mistral-small-latest"),
        .init(id: "togetherai", name: "Together.ai", baseURL: "https://api.together.xyz/v1", defaultModel: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"),
        .init(id: "cerebras", name: "Cerebras", baseURL: "https://api.cerebras.ai/v1", defaultModel: "llama3.1-8b"),
        .init(id: "moonshotai", name: "Moonshot AI", baseURL: "https://api.moonshot.ai/v1", defaultModel: "kimi-k2-turbo"),
        .init(id: "alibaba", name: "Alibaba Cloud", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen3.5-flash"),
        .init(id: "volcengine", name: "Volcengine", baseURL: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-seed-1-6-flash-250828"),
        .init(id: "xai", name: "xAI", baseURL: "https://api.x.ai/v1", defaultModel: "grok-4.20-non-reasoning"),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", defaultModel: "x-ai/grok-4-fast:free"),
    ]
}

@MainActor private final class TranslateModel: ObservableObject {
    @Published var input = ""
    @Published var result: TranslationPayload?
    @Published var providerName = ""
    @Published var error: String?
    @Published var isLoading = false
    @Published var hasKey = false
    @Published var currentHistoryEntryID: UUID?
    @Published var targetCode = "cmn"
    @Published var sourceCode = "auto"
    @Published var providerId = "deepseek"
    @Published var config: [String: Any] = [:]
    private let speech = AVSpeechSynthesizer()
    private let generationStore = NativeGenerationStore()
    let historyStore = TranslationHistoryStore()
    static let languages: [(String, String, String)] = [("cmn","简体中文","Chinese Simplified"),("cht","繁體中文","Chinese Traditional"),("eng","英语","English"),("jpn","日语","Japanese"),("kor","韩语","Korean"),("fra","法语","French"),("deu","德语","German"),("spa","西班牙语","Spanish"),("rus","俄语","Russian"),("ita","意大利语","Italian"),("por","葡萄牙语","Portuguese"),("ara","阿拉伯语","Arabic"),("hin","印地语","Hindi"),("ben","孟加拉语","Bengali"),("urd","乌尔都语","Urdu"),("ind","印度尼西亚语","Indonesian"),("msa","马来语","Malay"),("tha","泰语","Thai"),("vie","越南语","Vietnamese"),("tur","土耳其语","Turkish"),("nld","荷兰语","Dutch"),("swe","瑞典语","Swedish"),("nor","挪威语","Norwegian"),("dan","丹麦语","Danish"),("fin","芬兰语","Finnish"),("pol","波兰语","Polish"),("ukr","乌克兰语","Ukrainian"),("ces","捷克语","Czech"),("ell","希腊语","Greek"),("heb","希伯来语","Hebrew"),("fas","波斯语","Persian"),("tam","泰米尔语","Tamil"),("tel","泰卢固语","Telugu"),("mar","马拉地语","Marathi"),("guj","古吉拉特语","Gujarati"),("pan","旁遮普语","Punjabi"),("swa","斯瓦希里语","Swahili"),("ron","罗马尼亚语","Romanian"),("hun","匈牙利语","Hungarian"),("bul","保加利亚语","Bulgarian"),("hrv","克罗地亚语","Croatian"),("srp","塞尔维亚语","Serbian"),("slk","斯洛伐克语","Slovak"),("slv","斯洛文尼亚语","Slovenian"),("cat","加泰罗尼亚语","Catalan"),("eus","巴斯克语","Basque"),("glg","加利西亚语","Galician"),("isl","冰岛语","Icelandic"),("gle","爱尔兰语","Irish"),("cym","威尔士语","Welsh"),("est","爱沙尼亚语","Estonian"),("lav","拉脱维亚语","Latvian"),("lit","立陶宛语","Lithuanian"),("khm","高棉语","Khmer"),("lao","老挝语","Lao"),("mya","缅甸语","Burmese"),("nep","尼泊尔语","Nepali"),("sin","僧伽罗语","Sinhala"),("amh","阿姆哈拉语","Amharic"),("yor","约鲁巴语","Yoruba"),("zul","祖鲁语","Zulu"),("afr","南非荷兰语","Afrikaans"),("kaz","哈萨克语","Kazakh"),("uzb","乌兹别克语","Uzbek"),("mon","蒙古语","Mongolian"),("yid","意第绪语","Yiddish")]

    init() { reload() }

    func reload() {
        providerId = UserDefaults.standard.string(forKey: "opentranslate.native.provider") ?? providerId
        guard let envelope = SharedSettingsStore.shared.readEnvelope() else { hasKey = false; return }
        config = envelope.config
        targetCode = (config["language"] as? [String: Any])?["targetCode"] as? String ?? "cmn"
        sourceCode = (config["language"] as? [String: Any])?["sourceCode"] as? String ?? "auto"
        let providers = config["providersConfig"] as? [[String: Any]] ?? []
        let chosen = providers.first(where: { ($0["provider"] as? String) == providerId && !(($0["apiKey"] as? String ?? "").isEmpty) })
            ?? providers.first(where: { item in NativeProvider.all.contains(where: { $0.id == (item["provider"] as? String ?? "") }) && !(item["apiKey"] as? String ?? "").isEmpty })
        if let chosen, let id = chosen["provider"] as? String { providerId = id }
        hasKey = providers.contains { ($0["provider"] as? String) == providerId && !(($0["apiKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }

    func save(provider: NativeProvider, apiKey: String, model: String, baseURL: String, language: String, theme: String) -> Bool {
        var providers = config["providersConfig"] as? [[String: Any]] ?? []
        let index = providers.firstIndex { ($0["provider"] as? String) == provider.id }
        var item = index.map { providers[$0] } ?? ["id": "\(provider.id)-native", "name": provider.name, "enabled": true, "provider": provider.id]
        item["apiKey"] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        item["baseURL"] = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        item["model"] = ["model": model, "isCustomModel": true, "customModel": model]
        if let index { providers[index] = item } else { providers.append(item) }
        var updated = config
        updated["providersConfig"] = providers
        var lang = updated["language"] as? [String: Any] ?? [:]
        lang["targetCode"] = language
        updated["language"] = lang
        let timestamp = Date().timeIntervalSince1970 * 1000
        let write = SharedSettingsStore.shared.write(config: updated, schemaVersion: nativeSchemaVersion, lastModifiedAt: timestamp, source: "native-app", rejectIfOlder: false)
        guard write.ok else { return false }
        config = updated; providerId = provider.id; targetCode = language
        UserDefaults.standard.set(provider.id, forKey: "opentranslate.native.provider")
        UserDefaults.standard.set(theme, forKey: nativeThemeKey)
        reload()
        return true
    }

    func chooseLanguage(_ code: String, source: Bool) {
        if source { sourceCode = code } else { targetCode = code }
        var updated = config
        var lang = updated["language"] as? [String: Any] ?? [:]
        lang[source ? "sourceCode" : "targetCode"] = code
        updated["language"] = lang
        let write = SharedSettingsStore.shared.write(config: updated, schemaVersion: nativeSchemaVersion, lastModifiedAt: Date().timeIntervalSince1970 * 1000, source: "native-app", rejectIfOlder: false)
        if write.ok { config = updated }
    }

    func translate() async {
        await translate(imageData: nil)
    }

    func translate(imageData: Data?) async {
        error = nil
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageData == nil && text.isEmpty { error = "请输入要翻译的文字。"; return }
        guard let envelope = SharedSettingsStore.shared.readEnvelope() else { error = "添加 AI 提供商后即可翻译。"; return }
        let cfg = envelope.config
        let providers = cfg["providersConfig"] as? [[String: Any]] ?? []
        guard let item = providers.first(where: { ($0["provider"] as? String) == providerId }),
              let key = item["apiKey"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hasKey = false; error = "添加 AI 提供商后即可翻译。"; return
        }
        guard let provider = NativeProvider.all.first(where: { $0.id == providerId }) else { error = "该提供商暂不支持原生翻译。"; return }
        let base = (item["baseURL"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? provider.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else { error = "提供商地址无效。"; return }
        let modelObject = item["model"] as? [String: Any] ?? [:]
        let model = (modelObject["customModel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (modelObject["model"] as? String ?? provider.defaultModel)
        guard !model.isEmpty else { error = "请在设置中填写模型名。"; return }
        if imageData != nil && !Self.supportsVision(model) {
            error = "当前模型 \(model) 不支持图片输入，请在设置里换用多模态模型"; return
        }
        let languageName = Self.languageName(targetCode)
        let generationSettings = generationStore.settings
        let resolvedPrompt = generationStore.resolvedSystemPrompt(targetLanguage: languageName, input: text)
        let usesBuiltInPrompt = generationSettings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || generationSettings.systemPrompt == NativePromptDefaults.systemPrompt
        var system = resolvedPrompt
        if usesBuiltInPrompt {
            system = system.replacingOccurrences(of: "{{targetLanguage}}", with: languageName)
            if imageData != nil {
                system = system.replacingOccurrences(of: "将用户输入翻译为", with: "识别图片中文字并将其翻译为")
            }
        }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let userContent: Any
        if let imageData {
            userContent = [["type": "text", "text": system], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]]
        } else { userContent = text }
        let messages: [[String: Any]] = imageData == nil ? [["role": "system", "content": system], ["role": "user", "content": userContent]] : [["role": "user", "content": userContent]]
        var requestBody: [String: Any] = ["model": model, "messages": messages, "temperature": generationSettings.temperature]
        if generationSettings.maxTokens > 0 { requestBody["max_tokens"] = generationSettings.maxTokens }
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else { throw NSError(domain: "NativeTranslation", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务返回错误（HTTP \(http.statusCode)）。请检查提供商、模型和 API Key。"] ) }
            let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = completion.choices.first?.message.content, !content.isEmpty else { throw NSError(domain: "NativeTranslation", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务未返回翻译内容。"] ) }
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^```(?:json)?\\s*|\\s*```$", with: "", options: .regularExpression)
            if let parsed = try? JSONDecoder().decode(TranslationPayload.self, from: Data(cleaned.utf8)), let translation = parsed.translation, !translation.isEmpty {
                result = parsed
            } else { result = TranslationPayload(translation: cleaned, partOfSpeech: nil, ipa: nil, alternatives: nil, examples: nil, definitions: nil) }
            providerName = (item["name"] as? String) ?? provider.name
            if let translation = result?.translation {
                currentHistoryEntryID = historyStore.record(input: text, translation: translation, sourceCode: sourceCode, targetCode: targetCode, providerName: providerName)
            }
        } catch {
            self.error = (error as? URLError)?.code == .timedOut ? "请求超时（45 秒），请稍后重试。" : error.localizedDescription
        }
    }

    func speak(_ text: String, languageCode: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.bcp47(languageCode))
        speech.speak(utterance)
    }
    private static func languageName(_ code: String) -> String { languages.first(where: { $0.0 == code })?.1 ?? code }
    private static func supportsVision(_ model: String) -> Bool {
        let name = model.lowercased().split(separator: "/").last.map(String.init) ?? model.lowercased()
        return name.hasPrefix("gpt-4o") || name.hasPrefix("gpt-4.1") || name.hasPrefix("gpt-5") || name == "o3" || name.hasPrefix("o4") || name.hasPrefix("gemini") || name.hasPrefix("claude-3") || name.hasPrefix("claude-4") || name.hasPrefix("deepseek-vl")
    }
    func translatePDF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { error = "无法读取所选 PDF。"; return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let pdf = PDFDocument(url: url) else { error = "无法打开所选 PDF。"; return }
        let limit = min(pdf.pageCount, 10)
        let text = (0..<limit).compactMap { pdf.page(at: $0)?.string }.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "这是扫描版 PDF，请改用图片翻译"; return }
        input = text
        if pdf.pageCount > 10 { error = "长文档建议分段（本次仅翻译前 10 页）" }
        Task {
            await translate()
            if pdf.pageCount > 10 { error = "长文档建议分段（本次仅翻译前 10 页）" }
        }
    }
    func translateImage(_ data: Data) {
        #if os(iOS)
        guard let image = UIImage(data: data), let resized = image.resized(maxDimension: 1536), let jpeg = resized.jpegData(compressionQuality: 0.82) else { error = "无法读取所选图片。"; return }
        Task { await translate(imageData: jpeg) }
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { error = "无法读取所选图片。"; return }
        let ratio = min(1, 1536 / max(image.size.width, image.size.height))
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: max(1, Int(size.width)), pixelsHigh: max(1, Int(size.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { error = "无法压缩所选图片。"; return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { error = "无法编码所选图片。"; return }
        Task { await translate(imageData: jpeg) }
        #endif
    }
    private static func bcp47(_ code: String) -> String { ["cmn": "zh-CN", "eng": "en-US", "jpn": "ja-JP", "kor": "ko-KR", "fra": "fr-FR", "deu": "de-DE", "spa": "es-ES", "ita": "it-IT", "rus": "ru-RU"][code] ?? code }
}

struct TranslateScreen: View {
    @StateObject private var model = TranslateModel()
    @State private var editing = false
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var showingVoiceNotice = false
    @State private var showingSourceLanguages = false
    @State private var showingTargetLanguages = false
    @State private var showingHistorySheet = false
    @State private var showingDeleteCurrentConfirmation = false
    @State private var showingSwapNotice = false
    @State private var showingCameraNotice = false
    @State private var showingFileImporter = false
    #if os(iOS)
    @State private var pasteAvailable = false
    @State private var showingPhotoPicker = false
    #endif
    @State private var historyHeight: CGFloat = 0
    @State private var historyDragStart: CGFloat = 0
    @State private var historyIsDragging = false
    @State private var sourceDrag: CGFloat = 0
    @State private var targetDrag: CGFloat = 0
    @State private var sourceWidth: CGFloat = 0
    @State private var toastMessage: String?
    @AppStorage(nativeThemeKey) private var themePreference = "system"
    @FocusState private var editorFocused: Bool
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = min(420, max(260, geometry.size.height * 0.55))
            let maximumHistoryHeight = min(320, geometry.size.height * 0.42)
            ZStack {
                pageBackground.ignoresSafeArea()
                if model.result != nil {
                    resultScreen
                } else {
                    VStack(spacing: 0) {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                header
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                    .frame(maxWidth: 608)
                                if !model.hasKey {
                                    Button { showingSettings = true } label: {
                                        Label("添加 AI 提供商后即可翻译", systemImage: "key.fill")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 12)
                                    .frame(maxWidth: 608)
                                }
                                if let error = model.error {
                                    Text(error)
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .padding(.horizontal, 24)
                                        .frame(maxWidth: 608)
                                }

                                inputCard(height: cardHeight, maximumHistoryHeight: maximumHistoryHeight)
                                    .padding(.top, 12)

                                if historyHeight > 0 {
                                    historyPanel
                                        .frame(maxWidth: 560)
                                        .frame(height: historyHeight)
                                        .padding(.top, historyHeight)
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        actionBar
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                        languageBar
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                    }
#if os(macOS)
                    Button("切换历史记录") { toggleHistory(maximum: maximumHistoryHeight) }
                        .keyboardShortcut("h", modifiers: [.command, .shift])
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
                    Button("粘贴到卡片") { pasteIntoCard() }
                        .keyboardShortcut("v", modifiers: .command)
                        .disabled(editing)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
#endif
                }
                if let toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(hex: "303134"), in: Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 88)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .sheet(isPresented: $showingSettings) { NativeSettingsSheet(model: model) }
        .sheet(isPresented: $showingSourceLanguages) { LanguagePickerSheet(title: "源语言", selected: model.sourceCode, source: true) { model.chooseLanguage($0, source: true) }.modifier(LargeSheetDetent()) }
        .sheet(isPresented: $showingTargetLanguages) { LanguagePickerSheet(title: "目标语言", selected: model.targetCode, source: false) { model.chooseLanguage($0, source: false) }.modifier(LargeSheetDetent()) }
        .sheet(isPresented: $showingHistorySheet) {
            TranslationHistoryPanel(store: model.historyStore, height: 520, colorScheme: systemScheme) { entry in
                selectHistoryEntry(entry)
                showingHistorySheet = false
            }
            .padding(.top, 8)
            .modifier(LargeSheetDetent())
        }
        .confirmationDialog("删除这条记录？", isPresented: $showingDeleteCurrentConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCurrentHistoryEntry() }
            Button("取消", role: .cancel) {}
        }
        .alert("语音输入将在后续版本启用", isPresented: $showingVoiceNotice) { Button("好", role: .cancel) {} }
        .alert("拍照翻译将在后续版本启用", isPresented: $showingCameraNotice) { Button("好", role: .cancel) {} }
        .alert("无法交换语言", isPresented: $showingSwapNotice) { Button("好", role: .cancel) {} } message: { Text("源语言为自动检测时，请先选择具体源语言再交换。") }
        #if os(iOS)
        .sheet(isPresented: $showingPhotoPicker) {
            if #available(iOS 16.0, *) { NativePhotosPicker { model.translateImage($0) } }
            else { Text("照片选择需要 iOS 16 或更新版本。") }
        }
        #endif
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? (url.pathExtension.lowercased() == "pdf")
                if isPDF {
                    model.translatePDF(url: url)
                } else {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) { model.translateImage(data) }
                    else { model.error = "无法读取所选图片。" }
                }
            }
            else if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .onChange(of: editing) { active in if active { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true } } }
        .onAppear { model.reload(); refreshPasteboard() }
        .preferredColorScheme(themePreference == "light" ? .light : (themePreference == "dark" ? .dark : nil))
#if os(macOS)
        .onExitCommand { if editing { cancelEditing() } }
#endif
    }

    private var isDarkAppearance: Bool { systemScheme == .dark }
    private var pageBackground: Color { Color(hex: isDarkAppearance ? "131314" : "FFFFFF") }
    private var cardBackground: Color { Color(hex: isDarkAppearance ? "1F1F21" : "F1F3F4") }
    private var languageBackground: Color { Color(hex: isDarkAppearance ? "2B2C2E" : "F1F3F4") }
    private var historyBackground: Color { Color(hex: isDarkAppearance ? "1B1C1E" : "F8F9FA") }
    private var primaryTextColor: Color { Color(hex: isDarkAppearance ? "E8EAED" : "202124") }
    private var secondaryTextColor: Color { Color(hex: isDarkAppearance ? "9AA0A6" : "5F6368") }
    private var micFillColor: Color { Color(hex: isDarkAppearance ? "A8C7FA" : "1A73E8") }
    private var micGlyphColor: Color { isDarkAppearance ? Color(hex: "131314") : .white }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 42, height: 42)
            Spacer()
            Text("OpenTranslate").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 42, height: 42)
                    .background(languageBackground, in: Circle())
                    .overlay(Circle().stroke(isDarkAppearance ? .clear : Color(hex: "DADCE0"), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .frame(height: 42)
    }

    private func inputCard(height: CGFloat, maximumHistoryHeight: CGFloat) -> some View {
        ZStack {
            inputArea
                .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDarkAppearance ? Color.white.opacity(0.24) : Color.black.opacity(0.16))
                .frame(width: 44, height: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
                .allowsHitTesting(false)

        }
        .frame(maxWidth: 608)
        .frame(height: height)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: isDarkAppearance ? .clear : Color.black.opacity(0.08), radius: 24, x: 0, y: 8)
        .overlay(alignment: .bottom) {
            if !editing {
                Color.clear
                    .frame(width: 124, height: 48)
                    .contentShape(Rectangle())
                    .highPriorityGesture(historyGripGesture(maximum: maximumHistoryHeight))
                    .offset(y: 14)
                    .accessibilityElement()
                    .accessibilityLabel(historyHeight > 0 ? "收起历史记录" : "展开历史记录")
                    .accessibilityHint("轻点切换，或上下拖动历史记录面板")
            }
        }
        .offset(y: historyHeight)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(macOS)
            if editing {
                HStack {
                    Button("取消", action: cancelEditing)
                    Spacer()
                    Button("完成", action: commitEditing)
                }
                .font(.system(size: 13))
            }
            #endif

            if editing {
                editorView
                HStack { Spacer(); Text("\(draft.count) 字").font(.caption).foregroundStyle(secondaryTextColor) }
            } else {
                Text(model.input.isEmpty ? "输入文字" : model.input)
                    .font(.system(size: model.input.isEmpty ? 34 : 22, weight: .regular))
                    .foregroundStyle(model.input.isEmpty ? secondaryTextColor : primaryTextColor)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: beginEditing)
                if !model.input.isEmpty {
                    Text("\(model.input.count) 字").font(.caption).foregroundStyle(secondaryTextColor)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { if !editing { beginEditing() } }
    }

    private var historyPanel: some View {
        TranslationHistoryPanel(store: model.historyStore, height: historyHeight, colorScheme: systemScheme) { entry in
            selectHistoryEntry(entry)
        }
    }

    private func historyGripGesture(maximum: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !editing else { return }
                if !historyIsDragging {
                    historyIsDragging = true
                    historyDragStart = historyHeight
                }
                historyHeight = min(maximum, max(0, historyDragStart + value.translation.height))
            }
            .onEnded { value in
                guard !editing else { historyIsDragging = false; return }
                let vertical = value.translation.height
                let horizontal = value.translation.width

                if abs(vertical) < 6 && abs(horizontal) < 6 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        historyHeight = historyHeight > 0 ? 0 : maximum
                    }
                } else if abs(vertical) >= abs(horizontal) {
                    let projectedHeight = min(maximum, max(0, historyDragStart + value.predictedEndTranslation.height))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        historyHeight = projectedHeight > maximum * 0.35 ? maximum : 0
                    }
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { historyHeight = historyDragStart }
                }
                historyIsDragging = false
            }
    }

    private func beginEditing() {
        guard !editing else { return }
        draft = model.input
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            historyHeight = 0
            editing = true
        }
    }

    private func toggleHistory(maximum: CGFloat) {
        guard !editing else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            historyHeight = historyHeight > 0 ? 0 : maximum
        }
    }

    @ViewBuilder private var editorView: some View {
        #if os(iOS)
        ReturnCommitTextEditor(text: $draft, onSubmit: commitEditing)
        #else
        if #available(macOS 13.0, *) {
            TextEditor(text: $draft).scrollContentBackground(.hidden).focused($editorFocused).accessibilityLabel("输入待翻译文字")
        } else {
            TextEditor(text: $draft).focused($editorFocused).accessibilityLabel("输入待翻译文字")
        }
        #endif
    }
    private func cancelEditing() {
        guard editing else { return }
        draft = model.input
        editing = false
        editorFocused = false
    }
    private func commitEditing() {
        guard editing else { return }
        model.input = draft
        editing = false
        editorFocused = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { historyHeight = 0 }
        if model.hasKey { Task { await model.translate() } }
    }
    private var languageBar: some View {
        HStack(spacing: 0) {
            languagePill(source: true).background(GeometryReader { proxy in Color.clear.onAppear { sourceWidth = proxy.size.width } }).offset(x: sourceDrag)
            Button { swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 18)).foregroundStyle(secondaryTextColor).frame(width: 44, height: 44) }.buttonStyle(PressScaleStyle()).accessibilityLabel("交换语言")
            languagePill(source: false).offset(x: targetDrag)
        }.font(.system(size: 13))
    }
    private func languagePill(source: Bool) -> some View {
        Button { if source { showingSourceLanguages = true } else { showingTargetLanguages = true } } label: {
            Text(languageName(source ? model.sourceCode : model.targetCode))
                .foregroundStyle(primaryTextColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, 8)
                .background(languageBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDarkAppearance ? .clear : Color(hex: "DADCE0"), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(source ? "源语言" : "目标语言")
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in if source { sourceDrag = value.translation.width } else { targetDrag = value.translation.width } }.onEnded { value in
                let threshold = sourceWidth * 0.5
                if (source && (value.translation.width > threshold || value.predictedEndTranslation.width > threshold * 1.4)) || (!source && (value.translation.width < -threshold || value.predictedEndTranslation.width < -threshold * 1.4)) { swapLanguages() }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { sourceDrag = 0; targetDrag = 0 }
            })
    }
    private func swapLanguages() {
        guard model.sourceCode != "auto" else { showingSwapNotice = true; return }
        let old = model.sourceCode
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.chooseLanguage(model.targetCode, source: true); model.chooseLanguage(old, source: false) }
    }
    private var actionBar: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            ZStack {
            #if os(iOS)
                if pasteAvailable {
                    Button { pasteText() } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(primaryTextColor)
                            .frame(width: 44, height: 30)
                            .background(Color(hex: isDarkAppearance ? "2B2C2E" : "F1F3F4"), in: Capsule())
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("粘贴")
                    .position(x: centerX - 77, y: centerY)
                }
            #else
                EmptyView()
            #endif
                Button { showingVoiceNotice = true } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(micGlyphColor)
                        .frame(width: 86, height: 86)
                        .background(micFillColor, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("语音输入")
                .position(x: centerX, y: centerY)

                imageMenu
                    .frame(width: 44, height: 44)
                    .position(x: centerX + 77, y: centerY)
            }
        }
        .frame(height: 86)
    }
    private var imageMenu: some View {
        Menu {
            #if os(iOS)
            Button { showingCameraNotice = true } label: { Label("拍照", systemImage: "camera") }
            Button { showingPhotoPicker = true } label: { Label("从照片选择", systemImage: "photo.on.rectangle") }
            Button { showingFileImporter = true } label: { Label("选择文件", systemImage: "doc") }
            #else
            Button { showingFileImporter = true } label: { Label("从文件选择", systemImage: "doc") }
            #endif
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22))
                .foregroundStyle(primaryTextColor)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("相机和文件翻译")
    }
    private func refreshPasteboard() {
        #if os(iOS)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { pasteAvailable = UIPasteboard.general.hasStrings }
        #else
        return
        #endif
    }
    private func pasteText() {
        #if os(iOS)
        guard let text = UIPasteboard.general.string, !text.isEmpty else { refreshPasteboard(); return }
        model.result = nil
        model.input = text; draft = text
        if model.hasKey { Task { await model.translate() } } else { showingSettings = true }
        refreshPasteboard()
        #endif
    }
    #if os(macOS)
    private func pasteIntoCard() {
        guard !editing, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        model.result = nil
        model.input = text
        draft = text
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { historyHeight = 0 }
        if model.hasKey { Task { await model.translate() } } else { showingSettings = true }
    }
    #endif
    private var resultScreen: some View {
        VStack(spacing: 0) {
            resultHeader
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ZStack(alignment: .bottomTrailing) {
                ScrollView(showsIndicators: false) {
                    resultContent
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                }
                newTranslationButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity)

            languageBar
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: 608, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pageBackground)
    }

    private var resultHeader: some View {
        HStack {
            Button(action: returnToHome) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 18))
                    Text("返回").font(.system(size: 15))
                }
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(cardBackground, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            HStack(spacing: 18) {
                Button { showingHistorySheet = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("历史记录")

                Button(action: toggleCurrentSaved) {
                    Image(systemName: isCurrentResultSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasCurrentHistoryEntry)
                .accessibilityLabel(isCurrentResultSaved ? "取消收藏" : "收藏")

                resultActionsMenu
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(cardBackground, in: Capsule())
        }
        .frame(height: 44)
    }

    private var resultActionsMenu: some View {
        Menu {
            Button { copyToClipboard(model.input) } label: { Label("复制原文", systemImage: "doc.on.doc") }
            Button { copyToClipboard(model.result?.translation ?? "") } label: { Label("复制译文", systemImage: "doc.on.doc") }
            Button {
                if let text = model.result?.translation { model.speak(text, languageCode: model.targetCode) }
            } label: { Label("朗读译文", systemImage: "speaker.wave.2") }
            Button {
                toggleCurrentSaved()
            } label: { Label(isCurrentResultSaved ? "取消收藏" : "收藏", systemImage: isCurrentResultSaved ? "bookmark.slash" : "bookmark") }
            .disabled(!hasCurrentHistoryEntry)
            Button(role: .destructive) {
                showingDeleteCurrentConfirmation = true
            } label: { Label("删除这条记录", systemImage: "trash") }
            .disabled(!hasCurrentHistoryEntry)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18))
                .foregroundStyle(primaryTextColor)
                .frame(width: 28, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
    }

    private var isCurrentResultSaved: Bool {
        guard let id = model.currentHistoryEntryID else { return false }
        return model.historyStore.entries.first(where: { $0.id == id })?.isSaved ?? false
    }

    private var hasCurrentHistoryEntry: Bool {
        guard let id = model.currentHistoryEntryID else { return false }
        return model.historyStore.entries.contains(where: { $0.id == id })
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(languageName(model.sourceCode))
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
                Text(model.input)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let ipa = model.result?.ipa, !ipa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(ipa)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryTextColor)
                }
                HStack {
                    Button { model.speak(model.input, languageCode: model.sourceCode) } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 20))
                            .foregroundStyle(secondaryTextColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("朗读原文")
                    Spacer()
                    Button { copyToClipboard(model.input) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 20))
                            .foregroundStyle(secondaryTextColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制原文")
                }
                .padding(.top, 2)
            }

            GeometryReader { geometry in
                Rectangle()
                    .fill(Color(hex: isDarkAppearance ? "8AB4F8" : "1A73E8").opacity(isDarkAppearance ? 0.4 : 0.3))
                    .frame(width: geometry.size.width * 0.62, height: 1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 1)
            .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 14) {
                Text(languageName(model.targetCode))
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
                Text(model.result?.translation ?? "")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color(hex: isDarkAppearance ? "8AB4F8" : "1A73E8"))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 22) {
                    Button {
                        if let text = model.result?.translation { model.speak(text, languageCode: model.targetCode) }
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 20))
                            .foregroundStyle(secondaryTextColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("朗读译文")
                    Spacer()
                    Button { copyToClipboard(model.result?.translation ?? "") } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 20))
                            .foregroundStyle(secondaryTextColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制译文")
                    resultActionsMenu
                }
                .padding(.top, 2)
            }

            if let examples = model.result?.examples, !examples.isEmpty {
                examplesCard(examples)
                    .padding(.vertical, 18)
            }

            if hasDictionaryDetails {
                translationCard
                    .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasDictionaryDetails: Bool {
        let payload = model.result
        return !(payload?.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(payload?.definitions?.isEmpty ?? true)
            || !(payload?.alternatives?.isEmpty ?? true)
    }

    private var cardStroke: Color {
        Color(hex: isDarkAppearance ? "8AB4F8" : "1A73E8").opacity(0.55)
    }

    private func examplesCard(_ examples: [TranslationExample]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("“\(model.input)”的示例")
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)
            ForEach(examples) { example in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: isDarkAppearance ? "8AB4F8" : "1A73E8"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(example.source)
                            .font(.system(size: 15))
                            .foregroundStyle(primaryTextColor)
                        if !example.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(example.target)
                                .font(.system(size: 13))
                                .foregroundStyle(secondaryTextColor)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardStroke, lineWidth: 1))
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("“\(model.input)”的翻译")
                .font(.system(size: 13))
                .foregroundStyle(secondaryTextColor)

            if let partOfSpeech = model.result?.partOfSpeech,
               !partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(partOfSpeech)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            if let definitions = model.result?.definitions {
                ForEach(Array(definitions.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(size: 15))
                        .foregroundStyle(primaryTextColor)
                }
            }

            if let alternatives = model.result?.alternatives, !alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if model.result?.definitions?.isEmpty == false {
                        Text("近义词")
                            .font(.system(size: 13))
                            .foregroundStyle(secondaryTextColor)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(alternatives) { alternative in
                            Button { copyToClipboard(alternative.text) } label: {
                                Text(alternative.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: isDarkAppearance ? "8AB4F8" : "1A73E8"))
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .overlay(Capsule().stroke(Color(hex: "5F6368"), lineWidth: 1))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel([alternative.text, alternative.note].compactMap { $0 }.joined(separator: "，"))
                            .accessibilityHint("轻点复制这个词")
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(cardStroke, lineWidth: 1))
    }

    private var newTranslationButton: some View {
        Button(action: startNewTranslation) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 18))
                Text("新翻译").font(.system(size: 15))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Color(hex: isDarkAppearance ? "1D4973" : "1A73E8"), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("新翻译")
    }

    private func returnToHome() {
        model.result = nil
        model.currentHistoryEntryID = nil
        editorFocused = false
    }

    private func startNewTranslation() {
        model.input = ""
        model.result = nil
        model.currentHistoryEntryID = nil
        model.error = nil
        draft = ""
        editing = false
        editorFocused = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { historyHeight = 0 }
    }

    private func selectHistoryEntry(_ entry: HistoryEntry) {
        model.input = entry.input
        model.sourceCode = entry.sourceCode
        model.targetCode = entry.targetCode
        model.providerName = entry.providerName
        model.result = TranslationPayload(
            translation: entry.translation,
            partOfSpeech: nil,
            ipa: nil,
            alternatives: nil,
            examples: nil,
            definitions: nil
        )
        model.currentHistoryEntryID = entry.id
        draft = entry.input
        editing = false
        editorFocused = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { historyHeight = 0 }
    }

    private func deleteCurrentHistoryEntry() {
        guard let id = model.currentHistoryEntryID, hasCurrentHistoryEntry else { return }
        model.historyStore.delete(id: id)
        model.currentHistoryEntryID = nil
        model.result = nil
        showToast("已删除记录")
    }

    private func toggleCurrentSaved() {
        guard let id = model.currentHistoryEntryID, hasCurrentHistoryEntry else { return }
        let saved = !isCurrentResultSaved
        model.historyStore.setSaved(id: id, saved: saved)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        showToast(saved ? "已收藏" : "已取消收藏")
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        showToast("已复制")
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toastMessage == message {
                withAnimation(.easeOut(duration: 0.2)) { toastMessage = nil }
            }
        }
    }

    private func languageName(_ code: String) -> String { code == "auto" ? "自动检测" : (TranslateModel.languages.first(where: { $0.0 == code })?.1 ?? code) }
}

private struct TranslationHistoryPanel: View {
    private enum Segment: String, CaseIterable {
        case history = "历史记录"
        case saved = "已保存"
    }

    @ObservedObject var store: TranslationHistoryStore
    let height: CGFloat
    let colorScheme: ColorScheme
    let onSelect: (HistoryEntry) -> Void

    @State private var selectedSegment: Segment = .history
    @State private var showingClearConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: HistoryEntry?

    private var isDark: Bool { colorScheme == .dark }
    private var primaryText: Color { Color(hex: isDark ? "E8EAED" : "202124") }
    private var secondaryText: Color { Color(hex: isDark ? "9AA0A6" : "5F6368") }
    private var panelColor: Color { Color(hex: isDark ? "1B1C1E" : "F8F9FA") }
    private var displayedEntries: [HistoryEntry] {
        let entries = selectedSegment == .saved ? store.entries.filter(\.isSaved) : store.entries
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(Segment.allCases, id: \.self) { segment in
                        Button { withAnimation(.easeInOut(duration: 0.16)) { selectedSegment = segment } } label: {
                            Text(segment.rawValue)
                                .font(.system(size: 13, weight: selectedSegment == segment ? .semibold : .regular))
                                .foregroundStyle(primaryText)
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                                .background(selectedSegment == segment ? Color(hex: isDark ? "2B2C2E" : "E8EAED") : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                if selectedSegment == .history {
                    Button("清空") { showingClearConfirmation = true }
                        .font(.system(size: 13))
                        .foregroundStyle(secondaryText)
                        .disabled(store.entries.isEmpty)
                }
            }
            .padding(.bottom, 8)

            if displayedEntries.isEmpty {
                Text(selectedSegment == .saved ? "还没有已保存的记录" : "还没有翻译记录")
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedEntries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(panelColor, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .confirmationDialog("清空全部历史？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除这条记录", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let entryToDelete { store.delete(id: entryToDelete.id) }
                entryToDelete = nil
            }
            Button("取消", role: .cancel) { entryToDelete = nil }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button { onSelect(entry) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.input)
                        .font(.system(size: 15))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                Text(entry.translation)
                        .font(.system(size: 13))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if entry.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryText)
                }
                Text(relativeTime(entry.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryText)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                entryToDelete = entry
                showingDeleteConfirmation = true
            }
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60)) 分钟前" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600)) 小时前" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

#if os(iOS)
@available(iOS 16.0, *)
private struct NativePhotosPicker: View {
    let onSelect: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    var body: some View {
        PhotosPicker("从照片选择", selection: $selection, matching: .images).padding(24)
            .onChange(of: selection) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { onSelect(data) }
                    dismiss()
                }
            }
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// A text view whose Return key finishes editing instead of inserting a newline.
/// Pasting multi-line text still keeps its line breaks.
private struct ReturnCommitTextEditor: UIViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ReturnCommitTextEditor
        var focusedOnce = false
        init(_ parent: ReturnCommitTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                textView.resignFirstResponder()
                parent.onSubmit()
                return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.returnKeyType = .done
        view.accessibilityLabel = "输入待翻译文字"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if !context.coordinator.focusedOnce {
            context.coordinator.focusedOnce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in view?.becomeFirstResponder() }
        }
    }
}
#endif

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1).animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct LargeSheetDetent: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) { content.presentationDetents([.large]) }
        else { content }
    }
}

private struct LanguagePickerSheet: View {
    let title: String
    let selected: String
    let source: Bool
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var pinStore: LanguagePinStore
    @State private var pinnedCodes: [String]
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    init(title: String, selected: String, source: Bool, onSelect: @escaping (String) -> Void) {
        self.title = title
        self.selected = selected
        self.source = source
        self.onSelect = onSelect
        let knownCodes = Set(TranslateModel.languages.map(\.0))
        let store = LanguagePinStore(validCodes: knownCodes)
        _pinStore = State(initialValue: store)
        _pinnedCodes = State(initialValue: store.pinned)
    }

    private var isDark: Bool { colorScheme == .dark }
    private var pageColor: Color { Color(hex: isDark ? "131314" : "FFFFFF") }
    private var cardColor: Color { Color(hex: isDark ? "1F1F21" : "F1F3F4") }
    private var searchColor: Color { Color(hex: isDark ? "2B2C2E" : "F1F3F4") }
    private var primaryText: Color { Color(hex: isDark ? "E8EAED" : "202124") }
    private var secondaryText: Color { Color(hex: isDark ? "9AA0A6" : "5F6368") }
    private var selectedColor: Color { Color(hex: isDark ? "1D4973" : "1A73E8") }
    private var separatorColor: Color { Color(hex: isDark ? "2A2B2D" : "DADCE0") }
    private let suggestedCodes = ["eng", "cmn", "jpn", "kor", "spa", "fra"]

    private var filtered: [(String, String, String)] {
        TranslateModel.languages.filter(matches)
    }

    private var filteredPinned: [(String, String, String)] {
        pinnedCodes.compactMap { code in TranslateModel.languages.first(where: { $0.0 == code }) }
            .filter(matches)
    }

    private var suggestions: [(String, String, String)] {
        var items: [(String, String, String)] = []
        if source && matches(("auto", "检测语言", "auto")) {
            items.append(("auto", "检测语言", "auto"))
        }
        items += suggestedCodes.compactMap { code in
            guard !pinnedCodes.contains(code), let item = TranslateModel.languages.first(where: { $0.0 == code }), matches(item) else { return nil }
            return item
        }
        return items
    }

    private var groups: [(String, [(String, String, String)])] {
        Dictionary(grouping: filtered.filter { !pinnedCodes.contains($0.0) }, by: { String($0.2.prefix(1)).uppercased() })
            .map { ($0.key, $0.value.sorted { $0.2.localizedCaseInsensitiveCompare($1.2) == .orderedAscending }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 44, height: 44)
                        .background(searchColor, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
            }
            .overlay(alignment: .center) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(secondaryText)
                TextField("搜索", text: $query)
                    .font(.system(size: 15))
                    .foregroundStyle(primaryText)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(searchColor, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if !filteredPinned.isEmpty {
                                sectionTitle("已置顶的语言")
                                languageCard(filteredPinned)
                            }
                            if !suggestions.isEmpty {
                                sectionTitle("建议的语言")
                                languageCard(suggestions)
                            }
                            ForEach(groups, id: \.0) { letter, entries in
                                sectionTitle(letter).id(letter)
                                languageCard(entries)
                            }
                        }
                        .padding(.leading, 18)
                        .padding(.trailing, 24)
                        .padding(.top, 2)
                        .padding(.bottom, 24)
                        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: query)
                    }
                    VStack(spacing: 2) {
                        ForEach(alphabet, id: \.self) { letter in
                            Button(letter) {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { proxy.scrollTo(letter, anchor: .top) }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: isDark ? "8AB4F8" : "1A73E8"))
                            .frame(width: 16)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .background(pageColor.ignoresSafeArea())
    }

    private func matches(_ item: (String, String, String)) -> Bool {
        query.isEmpty || item.0.localizedCaseInsensitiveContains(query)
            || item.1.localizedCaseInsensitiveContains(query)
            || item.2.localizedCaseInsensitiveContains(query)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(secondaryText)
            .padding(.leading, 16)
    }

    private func languageCard(_ items: [(String, String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                languageRow(item)
                if item.0 != items.last?.0 {
                    Rectangle().fill(separatorColor).frame(height: 1).padding(.leading, 52)
                }
            }
        }
        .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private func languageRow(_ item: (String, String, String)) -> some View {
        let code = item.0
        let name = item.1
        let isPinned = pinStore.isPinned(code)

        return HStack(spacing: 12) {
            Button { if code != "auto" { togglePin(code) } } label: {
                Group {
                    if code == "auto" {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "8AB4F8"))
                    } else if isPinned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: isDark ? "E8EAED" : "202124"))
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: "5F6368"))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(code == "auto" ? "检测语言" : (isPinned ? "取消置顶 \(name)" : "置顶 \(name)"))
            .disabled(code == "auto")

            Button {
                onSelect(code)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 16))
                        .foregroundStyle(selected == code ? .white : primaryText)
                    Spacer(minLength: 0)
                    if selected == code {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .transition(.scale)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 56)
        .background(selected == code ? selectedColor : .clear)
        .contextMenu {
            if code != "auto" {
                Button {
                    togglePin(code)
                } label: {
                    Label(isPinned ? "取消置顶" : "置顶", systemImage: isPinned ? "pin.slash" : "pin")
                }
            }
        }
    }

    private func togglePin(_ code: String) {
        guard code != "auto" else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            pinStore.toggle(code)
            pinnedCodes = pinStore.pinned
        }
    }
}

private struct NativeSettingsSheet: View {
    @ObservedObject var model: TranslateModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID = "deepseek"
    @State private var apiKey = ""
    @State private var modelName = "deepseek-chat"
    @State private var baseURL = NativeProvider.all[0].baseURL
    @State private var target = "cmn"
    @State private var theme = "system"
    @State private var systemPrompt = ""
    @State private var temperature = 0.2
    @State private var maxTokens = 0
    @State private var saveError: String?
    @State private var showingDefaultPromptNotice = false
    @State private var showingFullSettings = false
    @State private var showingModels = false
    @State private var modelSearch = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    private let generationStore = NativeGenerationStore()
    private var modelCacheKey: String { ModelDirectory.cacheKey(baseURL: selected.id == "openai-compatible" ? baseURL : selected.baseURL, apiKey: apiKey) }
    private var filteredModels: [String] { availableModels.filter { modelSearch.isEmpty || $0.localizedCaseInsensitiveContains(modelSearch) } }
    private var selected: NativeProvider { NativeProvider.all.first(where: { $0.id == selectedID }) ?? NativeProvider.all[0] }
    var body: some View {
        NavigationView {
            Form {
                Section("翻译提供商") {
                    Picker("提供商", selection: $selectedID) { ForEach(NativeProvider.all) { provider in Text(provider.name + (hasKey(provider.id) ? " · 已配置 Key" : " · 未配置 Key")).tag(provider.id) } }.onChange(of: selectedID) { _ in loadProvider() }
                    SecureField("API Key", text: $apiKey).textContentType(.password)
                    HStack {
                        TextField("模型名", text: $modelName)
                        Button("获取列表") { openModelList() }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selected.id == "openai-compatible" && baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isFetchingModels)
                    }
                    if isFetchingModels { ProgressView("正在获取模型列表…") }
                    if let modelFetchError { Text(modelFetchError).foregroundStyle(.red) }
                    if selected.id == "openai-compatible" { TextField("API Base URL", text: $baseURL) }
                }
                Section("偏好") {
                    Picker("目标语言", selection: $target) {
                        ForEach(TranslateModel.languages.indices, id: \.self) { index in
                            Text(TranslateModel.languages[index].1).tag(TranslateModel.languages[index].0)
                        }
                    }
                }
                Section("AI 指令") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("系统提示词")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复默认") {
                                systemPrompt = NativePromptDefaults.systemPrompt
                                generationStore.setSystemPrompt(systemPrompt)
                                showingDefaultPromptNotice = true
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "8AB4F8"))
                        }

                        systemPromptEditor

                        Text("可用占位符：{{targetLanguage}} {{input}}（其余网页类占位符会替换为空）")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            promptPreset("直译", prompt: "忠实直译，保留原文结构，不要增删信息。")
                            promptPreset("意译", prompt: "译成自然通顺的中文，优先表达原意而不是逐字对应。")
                            promptPreset("口语", prompt: "译成口语化表达，像日常说话一样。")
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("生成参数") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", temperature))
                                .monospacedDigit()
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                        Text("越低越稳定，越高越发散")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: temperature) { value in
                        generationStore.setTemperature(value)
                        temperature = generationStore.settings.temperature
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("最大输出 tokens")
                            Spacer()
                            Text(maxTokens == 0 ? "不限" : "\(maxTokens)")
                                .monospacedDigit()
                            Stepper("最大输出 tokens", value: $maxTokens, in: 0...8192, step: 256)
                                .labelsHidden()
                                .accessibilityLabel("最大输出 tokens")
                        }
                        Text("0 表示不限制")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: maxTokens) { value in
                        generationStore.setMaxTokens(value)
                        maxTokens = generationStore.settings.maxTokens
                    }
                }
                Section("外观") {
                    Picker("外观", selection: $theme) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                }
                if let saveError { Text(saveError).foregroundStyle(.red) }
                Section { Button("完整设置 →") { showingFullSettings = true } }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        }
        .sheet(isPresented: $showingFullSettings) { OptionsWebView() }
        .sheet(isPresented: $showingModels) {
            NavigationView {
                List(filteredModels, id: \.self) { modelID in
                    Button {
                        modelName = modelID
                        showingModels = false
                    } label: {
                        HStack {
                            Text(modelID).font(.system(.body, design: .monospaced))
                            Spacer()
                            if modelID == modelName { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }.foregroundStyle(.primary)
                }
                .searchable(text: $modelSearch, prompt: "搜索模型")
                .navigationTitle("选择模型")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("刷新") { Task { await fetchModels() } }.disabled(isFetchingModels) }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { showingModels = false } }
                }
            }
            .modifier(LargeSheetDetent())
        }
        .alert("已填入默认提示词", isPresented: $showingDefaultPromptNotice) { Button("好", role: .cancel) {} }
        .onAppear {
            selectedID = model.providerId
            target = model.targetCode
            theme = UserDefaults.standard.string(forKey: nativeThemeKey) ?? "system"
            let settings = generationStore.settings
            systemPrompt = settings.systemPrompt
            temperature = settings.temperature
            maxTokens = settings.maxTokens
            loadProvider()
        }
    }

    @ViewBuilder private var promptTextEditor: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextEditor(text: $systemPrompt).scrollContentBackground(.hidden)
        } else {
            TextEditor(text: $systemPrompt)
        }
    }

    private var systemPromptEditor: some View {
        ZStack(alignment: .topLeading) {
            promptTextEditor
                .font(.system(size: 14))
                .padding(4)
                .accessibilityLabel("系统提示词")
            if systemPrompt.isEmpty {
                Text("留空则使用内置默认提示词")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120)
        .background(
            Color(hex: colorScheme == .dark ? "1F1F21" : "F1F3F4"),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: systemPrompt) { value in generationStore.setSystemPrompt(value) }
    }

    private func promptPreset(_ title: String, prompt: String) -> some View {
        Button(title) { systemPrompt = prompt }
            .font(.system(size: 12))
            .foregroundStyle(colorScheme == .dark ? Color(hex: "E8EAED") : Color(hex: "202124"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(colorScheme == .dark ? Color(hex: "2B2C2E") : Color(hex: "F1F3F4"), in: Capsule())
            .buttonStyle(.plain)
    }

    private func hasKey(_ id: String) -> Bool { let list = model.config["providersConfig"] as? [[String: Any]] ?? []; return list.contains { ($0["provider"] as? String) == id && !(($0["apiKey"] as? String ?? "").isEmpty) } }
    private func openModelList() {
        modelFetchError = nil
        availableModels = UserDefaults.standard.stringArray(forKey: modelCacheKey) ?? []
        if availableModels.isEmpty { Task { await fetchModels() } }
        else { showingModels = true }
    }
    private func loadProvider() {
        let list = model.config["providersConfig"] as? [[String: Any]] ?? []
        let item = list.first { ($0["provider"] as? String) == selectedID }
        apiKey = item?["apiKey"] as? String ?? ""
        baseURL = item?["baseURL"] as? String ?? selected.baseURL
        let modelConfig = item?["model"] as? [String: Any] ?? [:]
        modelName = (modelConfig["customModel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (modelConfig["model"] as? String ?? selected.defaultModel)
        modelFetchError = nil
        let cacheKey = ModelDirectory.cacheKey(baseURL: selected.id == "openai-compatible" ? baseURL : selected.baseURL, apiKey: apiKey)
        if let cached = UserDefaults.standard.stringArray(forKey: cacheKey), !cached.isEmpty { availableModels = cached }
        else { availableModels = [] }
    }
    private func fetchModels() async {
        modelFetchError = nil
        let endpointBase = selected.id == "openai-compatible" ? baseURL : selected.baseURL
        guard let url = ModelDirectory.requestURL(baseURL: endpointBase) else { modelFetchError = "API Base URL 无效。"; return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        isFetchingModels = true
        defer { isFetchingModels = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { modelFetchError = "服务器响应无效。"; return }
            guard (200..<300).contains(response.statusCode) else {
                switch response.statusCode {
                case 401: modelFetchError = "API Key 无效或已过期"
                case 404: modelFetchError = "该端点不支持 /models，请手动输入模型名"
                default: modelFetchError = "获取模型列表失败（HTTP \(response.statusCode)）"
                }
                return
            }
            let models = try ModelDirectory.parse(data)
            availableModels = models
            UserDefaults.standard.set(models, forKey: modelCacheKey)
            modelSearch = ""
            showingModels = true
        } catch {
            modelFetchError = (error as? URLError)?.code == .timedOut ? "请求超时，请检查网络或端点" : "获取模型列表失败：\(error.localizedDescription)"
        }
    }
    private func save() { guard model.save(provider: selected, apiKey: apiKey, model: modelName, baseURL: baseURL, language: target, theme: theme) else { saveError = "无法写入 App Group 设置。"; return }; dismiss() }
}

private struct OptionsWebView: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "options-app", withExtension: "html", subdirectory: "settings") {
                NativeWebView(url: url)
            } else {
                Text("找不到完整设置页面").padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(iOS)
private struct NativeWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { let view = WKWebView(); view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()); return view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
private struct NativeWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { let view = WKWebView(); view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()); return view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
