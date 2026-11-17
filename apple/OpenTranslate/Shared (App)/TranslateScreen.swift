import SwiftUI
import AVFoundation
import WebKit
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

let nativeScreenDefaultsKey = "opentranslate.nativeScreen.enabled"
private let nativeThemeKey = "opentranslate.app.theme"
private let nativeSchemaVersion = 80

extension View {
    @ViewBuilder func otGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)) }
        else { background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)) }
    }
    @ViewBuilder func otGlassCircle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { glassEffect(.regular, in: .circle) }
        else { background(.ultraThinMaterial, in: Circle()) }
    }
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
    @Published var targetCode = "cmn"
    @Published var sourceCode = "auto"
    @Published var providerId = "deepseek"
    @Published var config: [String: Any] = [:]
    private let speech = AVSpeechSynthesizer()
    static let languages: [(String, String)] = [("auto", "自动检测"), ("cmn", "简体中文"), ("cht", "繁體中文"), ("eng", "英语"), ("jpn", "日语"), ("kor", "韩语"), ("fra", "法语"), ("deu", "德语"), ("spa", "西班牙语"), ("rus", "俄语")]

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
        error = nil
        guard let text = Optional(input.trimmingCharacters(in: .whitespacesAndNewlines)), !text.isEmpty else { error = "请输入要翻译的文字。"; return }
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
        let languageName = Self.languageName(targetCode)
        let system = "你是专业翻译助手。将用户输入翻译为\(languageName)。只返回合法 JSON，不要 Markdown 或额外文字。结构：{\"translation\":\"主译文\",\"partOfSpeech\":\"词性或空\",\"ipa\":\"音标或空\",\"alternatives\":[{\"text\":\"其他译法\",\"note\":\"使用场景\"}],\"examples\":[{\"source\":\"原句\",\"target\":\"译文\"}],\"definitions\":[\"简短释义\"]}。"
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": text]], "temperature": 0.2])
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
    private static func languageName(_ code: String) -> String { ["cmn": "简体中文", "eng": "英语", "jpn": "日语", "kor": "韩语", "fra": "法语", "deu": "德语", "spa": "西班牙语", "ita": "意大利语", "rus": "俄语" ][code] ?? code }
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
    @AppStorage(nativeThemeKey) private var themePreference = "system"
    @FocusState private var editorFocused: Bool
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            ZStack {
                (systemScheme == .dark ? Color(red: 19/255, green: 19/255, blue: 20/255) : .white).ignoresSafeArea()
                VStack(spacing: 0) {
                    header.padding(.horizontal, 24).padding(.top, 8)
                    advancedPill.padding(.top, 12)
                    if !model.hasKey { Button { showingSettings = true } label: { Label("添加 AI 提供商后即可翻译", systemImage: "key.fill").frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 12) }
                    if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(12).padding(.horizontal, 24) }
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
                }
            }
        }
        .sheet(isPresented: $showingSettings) { NativeSettingsSheet(model: model) }
        .alert("语音输入将在后续版本启用", isPresented: $showingVoiceNotice) { Button("好", role: .cancel) {} }
        .alert("无法交换语言", isPresented: $showingSwapNotice) { Button("好", role: .cancel) {} } message: { Text("源语言为自动检测时，请先选择具体源语言再交换。") }
        .onChange(of: editing) { active in if active { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true } } }
        .onAppear { model.reload() }
        .preferredColorScheme(themePreference == "light" ? .light : (themePreference == "dark" ? .dark : nil))
    }

    private var header: some View {
        HStack {
            Button { model.result = nil } label: { Image(systemName: "bookmark").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 42, height: 42) }.buttonStyle(.plain).otGlassCircle().accessibilityLabel("已保存")
            Spacer()
            Text("OpenTranslate").font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { showingSettings = true } label: { Image(systemName: "person.crop.circle.fill").font(.system(size: 24)).foregroundStyle(.secondary).frame(width: 42, height: 42) }.buttonStyle(.plain).accessibilityLabel("设置")
        }.frame(height: 42)
    }
    private var advancedPill: some View {
        Text("高级").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 26).otGlass(cornerRadius: 13)
    }
    // Deliberately transparent: the editor occupies the page background, never a card.
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                HStack { Button("取消") { draft = model.input; editing = false }; Spacer(); Button { model.input = draft; editing = false; if model.hasKey { Task { await model.translate() } } } label: { Text("完成").font(.system(size: 16, weight: .semibold)) } }
                editorView
                HStack { Spacer(); Text("\(draft.count) 字").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack(alignment: .top) {
                    Button { draft = model.input; editing = true } label: {
                        Text(model.input.isEmpty ? "输入文字" : model.input).font(.system(size: model.input.isEmpty ? 34 : 22, weight: .regular)).foregroundStyle(model.input.isEmpty ? Color.secondary : Color.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("编辑输入文字")
                    Button { draft = model.input; editing = true } label: { Image(systemName: "scribble").font(.system(size: 24)).foregroundStyle(.secondary).frame(width: 32, height: 40) }.buttonStyle(.plain).accessibilityLabel("编辑文字")
                }
                if !model.input.isEmpty { Text("\(model.input.count) 字").font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Button { showingSourceLanguages = true } label: { Text(languageName(model.sourceCode)).frame(maxWidth: .infinity).frame(height: 44).padding(.horizontal, 8).otGlass(cornerRadius: 12) }.buttonStyle(.plain).accessibilityLabel("源语言")
            Button { if model.sourceCode == "auto" { showingSwapNotice = true } else { let oldSource = model.sourceCode; model.chooseLanguage(model.targetCode, source: true); model.chooseLanguage(oldSource, source: false) } } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 18)).frame(width: 60, height: 44) }.buttonStyle(.plain).accessibilityLabel("交换语言")
            Button { showingTargetLanguages = true } label: { Text(languageName(model.targetCode)).frame(maxWidth: .infinity).frame(height: 44).padding(.horizontal, 8).otGlass(cornerRadius: 12) }.buttonStyle(.plain).accessibilityLabel("目标语言")
        }.font(.system(size: 14))
        .confirmationDialog("源语言", isPresented: $showingSourceLanguages, titleVisibility: .visible) { ForEach(TranslateModel.languages, id: \.0) { code, name in Button(name) { model.chooseLanguage(code, source: true) } } }
        .confirmationDialog("目标语言", isPresented: $showingTargetLanguages, titleVisibility: .visible) { ForEach(TranslateModel.languages.filter { $0.0 != "auto" }, id: \.0) { code, name in Button(name) { model.chooseLanguage(code, source: false) } } }
    }
    private var actionBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            actionItem("person.2.wave.2", title: "实时翻译")
            actionItem("camera.viewfinder", title: "相机")
            actionItem("graduationcap", title: "练习")
            Button { showingVoiceNotice = true } label: {
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill").font(.system(size: 28)).foregroundStyle(systemScheme == .dark ? Color(red: 19/255, green: 19/255, blue: 20/255) : .white).frame(width: 70, height: 70).background(systemScheme == .dark ? Color(red: 168/255, green: 199/255, blue: 250/255) : Color(red: 26/255, green: 115/255, blue: 232/255), in: Circle())
                    Text("语音").font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 16)
                }
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
        }
    }
    private func actionItem(_ symbol: String, title: String) -> some View {
        VStack(spacing: 8) { Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(systemScheme == .dark ? Color(red: 138/255, green: 180/255, blue: 248/255) : Color(red: 26/255, green: 115/255, blue: 232/255)).frame(width: 44, height: 44).otGlassCircle(); Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(height: 16) }.frame(maxWidth: .infinity)
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
    private func languageName(_ code: String) -> String { TranslateModel.languages.first(where: { $0.0 == code })?.1 ?? code }
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
    private var selected: NativeProvider { NativeProvider.all.first(where: { $0.id == selectedID }) ?? NativeProvider.all[0] }
    var body: some View {
        NavigationView {
            Form {
                Section("翻译提供商") {
                    Picker("提供商", selection: $selectedID) { ForEach(NativeProvider.all) { provider in Text(provider.name + (hasKey(provider.id) ? " · 已配置 Key" : " · 未配置 Key")).tag(provider.id) } }.onChange(of: selectedID) { _ in loadProvider() }
                    SecureField("API Key", text: $apiKey).textContentType(.password)
                    TextField("模型名", text: $modelName)
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
        .onAppear { selectedID = model.providerId; target = model.targetCode; theme = UserDefaults.standard.string(forKey: nativeThemeKey) ?? "system"; loadProvider() }
    }
    private func hasKey(_ id: String) -> Bool { let list = model.config["providersConfig"] as? [[String: Any]] ?? []; return list.contains { ($0["provider"] as? String) == id && !(($0["apiKey"] as? String ?? "").isEmpty) } }
    private func loadProvider() {
        let list = model.config["providersConfig"] as? [[String: Any]] ?? []
        let item = list.first { ($0["provider"] as? String) == selectedID }
        apiKey = item?["apiKey"] as? String ?? ""
        baseURL = item?["baseURL"] as? String ?? selected.baseURL
        let modelConfig = item?["model"] as? [String: Any] ?? [:]
        modelName = (modelConfig["customModel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (modelConfig["model"] as? String ?? selected.defaultModel)
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
        .frame(minWidth: 320, minHeight: 480)
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
