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

private enum TranslateMode: String, CaseIterable { case text = "文字", image = "图片", document = "文档" }

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
    @Published var mode: TranslateMode = .text
    @Published var hasKey = false
    @Published var targetCode = "cmn"
    @Published var sourceCode = "auto"
    @Published var providerId = "deepseek"
    @Published var config: [String: Any] = [:]
    private let speech = AVSpeechSynthesizer()
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
        let system = "你是专业翻译助手。\(imageData == nil ? "将用户输入" : "识别图片中文字并将其")翻译为\(languageName)。只返回合法 JSON，不要 Markdown 或额外文字。结构：{\"translation\":\"主译文\",\"partOfSpeech\":\"词性或空\",\"ipa\":\"音标或空\",\"alternatives\":[{\"text\":\"其他译法\",\"note\":\"使用场景\"}],\"examples\":[{\"source\":\"原句\",\"target\":\"译文\"}],\"definitions\":[\"简短释义\"]}。"
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let userContent: Any
        if let imageData {
            userContent = [["type": "text", "text": system], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]]]
        } else { userContent = text }
        let messages: [[String: Any]] = imageData == nil ? [["role": "system", "content": system], ["role": "user", "content": userContent]] : [["role": "user", "content": userContent]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": messages, "temperature": 0.2])
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
        } catch {
            self.error = (error as? URLError)?.code == .timedOut ? "请求超时（45 秒），请稍后重试。" : error.localizedDescription
        }
    }

    func speak() { guard let text = result?.translation else { return }; let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: Self.bcp47(targetCode)); speech.speak(utterance) }
    func copy() {
        guard let text = result?.translation else { return }
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
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
    @State private var showingSwapNotice = false
    @State private var showingCameraNotice = false
    @State private var showingPDFImporter = false
    #if os(iOS)
    @State private var pasteAvailable = false
    @State private var showingUploadMenu = false
    @State private var showingPhotoPicker = false
    #endif
    @State private var sourceDrag: CGFloat = 0
    @State private var targetDrag: CGFloat = 0
    @State private var sourceWidth: CGFloat = 0
    @AppStorage(nativeThemeKey) private var themePreference = "system"
    @FocusState private var editorFocused: Bool
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            ZStack {
                #if os(macOS)
                Color(hex: systemScheme == .dark ? "131314" : "FFFFFF").ignoresSafeArea()
                #else
                OTColor.background.ignoresSafeArea()
                #endif
                VStack(spacing: 0) {
                    header.padding(.horizontal, 24).padding(.top, 8)
                    if !model.hasKey { Button { showingSettings = true } label: { Label("添加 AI 提供商后即可翻译", systemImage: "key.fill").frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 12) }
                    if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(12).padding(.horizontal, 24) }
                    #if os(macOS)
                    modeTabs.padding(.horizontal, 24).padding(.top, 16)
                    languageBar.padding(.horizontal, 24).padding(.top, 12)
                    HStack(alignment: .top, spacing: 16) {
                        macInputCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                        macOutputCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.padding(.horizontal, 24).padding(.top, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
                    #else
                    if wide {
                        HStack(alignment: .top, spacing: 24) {
                            inputArea.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            Group { if model.result != nil { resultCard } else { emptyResult } }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.padding(.horizontal, 24).padding(.top, 16).frame(maxHeight: .infinity)
                    } else if model.result != nil { resultCard.padding(.horizontal, 24).padding(.top, 16).frame(maxHeight: .infinity) }
                    else { inputArea.padding(.horizontal, 24).padding(.top, 16).frame(maxHeight: .infinity, alignment: .topLeading) }
                    if model.result == nil {
                        languageBar.padding(.horizontal, 24)
                        actionBar.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 20)
                    }
                    #endif
                }
            }
        }
        .sheet(isPresented: $showingSettings) { NativeSettingsSheet(model: model) }
        .sheet(isPresented: $showingSourceLanguages) { LanguagePickerSheet(title: "源语言", selected: model.sourceCode, source: true) { model.chooseLanguage($0, source: true) }.modifier(LargeSheetDetent()) }
        .sheet(isPresented: $showingTargetLanguages) { LanguagePickerSheet(title: "目标语言", selected: model.targetCode, source: false) { model.chooseLanguage($0, source: false) }.modifier(LargeSheetDetent()) }
        .alert("语音输入将在后续版本启用", isPresented: $showingVoiceNotice) { Button("好", role: .cancel) {} }
        .alert("拍照翻译将在后续版本启用", isPresented: $showingCameraNotice) { Button("好", role: .cancel) {} }
        .alert("无法交换语言", isPresented: $showingSwapNotice) { Button("好", role: .cancel) {} } message: { Text("源语言为自动检测时，请先选择具体源语言再交换。") }
        #if os(iOS)
        .confirmationDialog("上传", isPresented: $showingUploadMenu, titleVisibility: .visible) {
            Button("从照片选择") { showingPhotoPicker = true }
            Button("选择文档") { showingPDFImporter = true }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            if #available(iOS 16.0, *) { NativePhotosPicker { model.translateImage($0) } }
            else { Text("照片选择需要 iOS 16 或更新版本。") }
        }
        #endif
        .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: model.mode == .image ? [.image] : [.pdf], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                if model.mode == .image {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) { model.translateImage(data) }
                    else { model.error = "无法读取所选图片。" }
                } else { model.translatePDF(url: url) }
            }
            else if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .onChange(of: editing) { active in if active { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true } } }
        .onAppear { model.reload(); refreshPasteboard() }
        .preferredColorScheme(themePreference == "light" ? .light : (themePreference == "dark" ? .dark : nil))
    }

    #if os(macOS)
    private var modeTabs: some View {
        HStack(spacing: 8) {
            ForEach(TranslateMode.allCases, id: \.self) { mode in
                Button { model.mode = mode } label: {
                    Text(mode.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(model.mode == mode ? Color(hex: systemScheme == .dark ? "AEC6F5" : "0B57D0") : Color(hex: systemScheme == .dark ? "9AA0A6" : "5F6368"))
                        .padding(.horizontal, 16).frame(height: 36).background(model.mode == mode ? Color(hex: systemScheme == .dark ? "1D4973" : "D3E3FD") : .clear, in: Capsule())
                        .overlay(Capsule().stroke(model.mode == mode ? .clear : Color(hex: "747775"), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var macInputCard: some View {
        VStack(alignment: .leading) {
            if model.mode == .text {
                if editing {
                    HStack { Button("取消") { draft = model.input; editing = false }; Spacer(); Button("完成") { model.input = draft; editing = false; if model.hasKey { Task { await model.translate() } } } }
                    editorView
                } else {
                    Text(model.input.isEmpty ? "输入文字" : model.input).font(.system(size: model.input.isEmpty ? 20 : 18)).foregroundStyle(Color(hex: model.input.isEmpty ? (systemScheme == .dark ? "9AA0A6" : "5F6368") : (systemScheme == .dark ? "E8EAED" : "202124"))).onTapGesture { draft = model.input; editing = true }
                }
            } else {
                Text(model.mode == .image ? "选择图片后翻译" : "选择 PDF 文档翻译").font(.system(size: 20)).foregroundStyle(Color(hex: systemScheme == .dark ? "9AA0A6" : "5F6368"))
            }
            Spacer(minLength: 0)
            if model.mode != .text {
                Button(model.mode == .image ? "选择图片" : "选择 PDF") { showingPDFImporter = true }.buttonStyle(.bordered)
            } else if !model.input.isEmpty { Button("翻译") { Task { await model.translate() } }.buttonStyle(.borderedProminent) }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: systemScheme == .dark ? "131314" : "FFFFFF"), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: systemScheme == .dark ? "3C4043" : "E0E0E0"), lineWidth: 1))
    }
    private var macOutputCard: some View {
        Group { if let result = model.result?.translation { Text(result).font(.system(size: 20)).foregroundStyle(Color(hex: systemScheme == .dark ? "E8EAED" : "202124")).textSelection(.enabled) } else { Text("翻译").font(.system(size: 20)).foregroundStyle(Color(hex: systemScheme == .dark ? "9AA0A6" : "5F6368")) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            .background(Color(hex: systemScheme == .dark ? "1F1F21" : "F5F7F9"), in: RoundedRectangle(cornerRadius: 8))
    }
    #endif

    private var header: some View {
        HStack {
            Color.clear.frame(width: 42, height: 42)
            Spacer()
            Text("OpenTranslate").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { showingSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(OTColor.secondary).frame(width: 42, height: 42).background(OTColor.panel, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("设置")
        }.frame(height: 42)
    }
    // Deliberately transparent: the editor occupies the page background, never a card.
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                HStack { Button("取消") { draft = model.input; editing = false }; Spacer(); Button { model.input = draft; editing = false; if model.hasKey { Task { await model.translate() } } } label: { Text("完成").font(.system(size: 16, weight: .semibold)) } }
                editorView
                HStack { Spacer(); Text("\(draft.count) 字").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(model.input.isEmpty ? "输入文字" : model.input).font(.system(size: model.input.isEmpty ? 34 : 22, weight: .regular)).foregroundStyle(model.input.isEmpty ? OTColor.secondary : OTColor.primary).frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .contentShape(Rectangle()).onTapGesture { draft = model.input; withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { editing = true } }
                #if os(iOS)
                if pasteAvailable {
                    Button { pasteText() } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 14)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 30).background(OTColor.blue, in: Capsule()) }
                        .buttonStyle(PressScaleStyle()).padding(.top, 8).transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                #endif
                if !model.input.isEmpty { Text("\(model.input.count) 字").font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle()).onTapGesture { if !editing { draft = model.input; withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { editing = true } } }
    }
    @ViewBuilder private var editorView: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextEditor(text: $draft).scrollContentBackground(.hidden).focused($editorFocused).accessibilityLabel("输入待翻译文字")
        } else {
            TextEditor(text: $draft).focused($editorFocused).accessibilityLabel("输入待翻译文字")
        }
    }
    private var languageBar: some View {
        HStack(spacing: 0) {
            languagePill(source: true).background(GeometryReader { proxy in Color.clear.onAppear { sourceWidth = proxy.size.width } }).offset(x: sourceDrag)
            Button { swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 18)).foregroundStyle(OTColor.secondary).frame(width: 44, height: 44) }.buttonStyle(PressScaleStyle()).accessibilityLabel("交换语言")
            languagePill(source: false).offset(x: targetDrag)
        }.font(.system(size: 13))
    }
    private func languagePill(source: Bool) -> some View {
        Button { if source { showingSourceLanguages = true } else { showingTargetLanguages = true } } label: {
            #if os(macOS)
            VStack(spacing: 0) {
                Text(languageName(source ? model.sourceCode : model.targetCode)).foregroundStyle(Color(hex: systemScheme == .dark ? "E8EAED" : "202124")).frame(maxWidth: .infinity).frame(height: 42).padding(.horizontal, 8)
                Rectangle().fill(Color(hex: systemScheme == .dark ? "AEC6F5" : "0B57D0")).frame(height: 2)
            }.frame(maxWidth: .infinity).frame(height: 44)
            #else
            Text(languageName(source ? model.sourceCode : model.targetCode)).foregroundStyle(OTColor.primary).frame(maxWidth: .infinity).frame(height: 44).padding(.horizontal, 8).background(OTColor.panel, in: RoundedRectangle(cornerRadius: 12))
            #endif
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
        HStack(spacing: 0) {
            #if os(iOS)
            Button { showingUploadMenu = true } label: { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.white).frame(width: 44, height: 44).background(Color(hex: "1D4973"), in: Circle()) }.buttonStyle(PressScaleStyle()).frame(maxWidth: .infinity).accessibilityLabel("上传")
            #else
            Color.clear.frame(maxWidth: .infinity)
            #endif
            Button { showingVoiceNotice = true } label: { Image(systemName: "mic.fill").font(.system(size: 28)).foregroundStyle(OTColor.background).frame(width: 70, height: 70).background(OTColor.mic, in: Circle()) }.buttonStyle(PressScaleStyle()).frame(maxWidth: .infinity)
            Button { showingCameraNotice = true } label: { Image(systemName: "camera.viewfinder").font(.system(size: 18)).foregroundStyle(.white).frame(width: 44, height: 44).background(OTColor.blue, in: Circle()) }.buttonStyle(PressScaleStyle()).frame(maxWidth: .infinity)
        }
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
        model.input = text; draft = text
        if model.hasKey { Task { await model.translate() } } else { showingSettings = true }
        refreshPasteboard()
        #endif
    }
    private var emptyResult: some View { Text("译文会显示在这里").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20) }
    private var resultCard: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { Button { model.result = nil } label: { Label("返回", systemImage: "chevron.left") }; Spacer() }
            Text(model.result?.translation ?? "").font(.system(size: 30, weight: .semibold)).textSelection(.enabled)
            HStack(spacing: 12) { Button { model.copy() } label: { Label("复制", systemImage: "doc.on.doc") }; Button { model.speak() } label: { Label("朗读", systemImage: "speaker.wave.2") } }.buttonStyle(.bordered)
            if let pos = model.result?.partOfSpeech, !pos.isEmpty { Text(pos + ((model.result?.ipa?.isEmpty == false) ? " · \(model.result!.ipa!)" : "")).font(.subheadline).foregroundStyle(.secondary) }
            if let definitions = model.result?.definitions, !definitions.isEmpty { section("释义") { ForEach(definitions, id: \.self) { Text("• \($0)") } } }
            if let alternatives = model.result?.alternatives, !alternatives.isEmpty { section("其他译法") { ForEach(alternatives) { item in VStack(alignment: .leading) { Text(item.text).fontWeight(.medium); if let note = item.note { Text(note).font(.caption).foregroundStyle(.secondary) } } } } }
            if let examples = model.result?.examples, !examples.isEmpty { section("例句") { ForEach(examples) { item in VStack(alignment: .leading, spacing: 4) { Text(item.source); Text(item.target).foregroundStyle(.secondary) }.padding(.vertical, 3) } } }
            Text("由 \(model.providerName) 生成 · AI 结果仅供参考").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20) }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); content() } }
    private func languageName(_ code: String) -> String { code == "auto" ? "自动检测" : (TranslateModel.languages.first(where: { $0.0 == code })?.1 ?? code) }
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
    @State private var query = ""
    @State private var pinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedLanguageCodes") ?? ["cmn", "cht", "eng", "jpn", "kor"])
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private var filtered: [(String, String, String)] {
        TranslateModel.languages.filter { item in query.isEmpty || item.0.localizedCaseInsensitiveContains(query) || item.1.localizedCaseInsensitiveContains(query) || item.2.localizedCaseInsensitiveContains(query) }
    }
    private var filteredPinned: [(String, String, String)] { filtered.filter { pinned.contains($0.0) }.sorted { $0.1.localizedCompare($1.1) == .orderedAscending } }
    private var groups: [(String, [(String, String, String)])] {
        Dictionary(grouping: filtered.filter { !pinned.contains($0.0) }, by: { String($0.2.prefix(1)).uppercased() }).map { ($0.key, $0.value.sorted { $0.2 < $1.2 }) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(OTColor.primary).frame(width: 36, height: 36).background(OTColor.search, in: Circle()) }.buttonStyle(PressScaleStyle()) }
                .overlay(alignment: .center) { Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(OTColor.primary).allowsHitTesting(false) }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
            HStack(spacing: 10) { Image(systemName: "magnifyingglass").foregroundStyle(OTColor.secondary); TextField("搜索", text: $query).font(.system(size: 14)).foregroundStyle(OTColor.primary).autocorrectionDisabled() }
                .padding(.horizontal, 14).frame(height: 44).background(OTColor.search, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 20).padding(.bottom, 20)
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            sectionTitle("已置顶的语言")
                            languageCard(filteredPinned, proxy: proxy)
                            sectionTitle("建议的语言")
                            languageCard((source ? [("auto", "检测语言", "auto")] : []) + filtered.filter { ["eng","cmn","jpn","kor","spa","fra"].contains($0.0) && !pinned.contains($0.0) }, proxy: proxy, detection: source)
                            ForEach(groups, id: \.0) { letter, entries in
                                Text(letter).font(.system(size: 13, weight: .semibold)).foregroundStyle(OTColor.secondary).id(letter).padding(.leading, 16)
                                languageCard(entries, proxy: proxy)
                            }
                        }.padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 24).offset(y: 0)
                            .transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(response: 0.42, dampingFraction: 0.85), value: query)
                    }
                    VStack(spacing: 2) { ForEach(alphabet, id: \.self) { letter in Button(letter) { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { proxy.scrollTo(letter, anchor: .top) } }.font(.system(size: 11)).foregroundStyle(Color(red: 138/255, green: 180/255, blue: 248/255)).frame(width: 16) } }.padding(.trailing, 2)
                }
            }
        }.background(OTColor.panel.ignoresSafeArea()).preferredColorScheme(.dark)
    }
    private func sectionTitle(_ text: String) -> some View { Text(text).font(.system(size: 13)).foregroundStyle(OTColor.secondary).padding(.leading, 16) }
    private func languageCard(_ items: [(String, String, String)], proxy: ScrollViewProxy, detection: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.0) { code, name, english in
                HStack(spacing: 12) {
                    Group {
                        if code == "auto" { Image(systemName: "sparkles").foregroundStyle(Color(red: 138/255, green: 180/255, blue: 248/255)) }
                        else if pinned.contains(code) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white) }
                        else { Color.clear }
                    }.font(.system(size: 18)).frame(width: 18)
                    Text(name).font(.system(size: 16)).foregroundStyle(OTColor.primary)
                    Spacer()
                    if selected == code { Image(systemName: "checkmark").font(.system(size: 18)).foregroundStyle(.white).scaleEffect(1).transition(.scale) }
                }.padding(.horizontal, 16).frame(height: 56).background(selected == code ? OTColor.selected : Color.clear)
                    .contentShape(Rectangle()).onTapGesture { onSelect(code); dismiss() }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { togglePin(code) } label: { Label(pinned.contains(code) ? "取消置顶" : "置顶", systemImage: pinned.contains(code) ? "pin.slash" : "pin.fill") }.tint(OTColor.yellow)
                    }
                if code != items.last?.0 { Rectangle().fill(OTColor.separator).frame(height: 1).padding(.leading, 52) }
            }
        }.background(OTColor.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func togglePin(_ code: String) { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { if pinned.contains(code) { pinned.remove(code) } else { pinned.insert(code) }; UserDefaults.standard.set(Array(pinned), forKey: "pinnedLanguageCodes") } }
}

private struct NativeSettingsSheet: View {
    @ObservedObject var model: TranslateModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "deepseek"
    @State private var apiKey = ""
    @State private var modelName = "deepseek-chat"
    @State private var baseURL = NativeProvider.all[0].baseURL
    @State private var target = "cmn"
    @State private var theme = "system"
    @State private var saveError: String?
    @State private var showingFullSettings = false
    @State private var showingModels = false
    @State private var modelSearch = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
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
                    Picker("目标语言", selection: $target) { Text("简体中文").tag("cmn"); Text("英语").tag("eng"); Text("日语").tag("jpn"); Text("韩语").tag("kor"); Text("法语").tag("fra"); Text("德语").tag("deu"); Text("西班牙语").tag("spa"); Text("意大利语").tag("ita"); Text("俄语").tag("rus") }
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
        .onAppear { selectedID = model.providerId; target = model.targetCode; theme = UserDefaults.standard.string(forKey: nativeThemeKey) ?? "system"; loadProvider() }
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
