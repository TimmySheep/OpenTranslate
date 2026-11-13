//
//  ViewController.swift
//  Shared (App)
//
//  Companion app: extension enablement + same-device shared settings status/editor.
//

import WebKit

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "net.timhuang.opentranslate.extension"

/// App-local theme key. Theme is not part of the App Group config protocol.
private let appThemeDefaultsKey = "opentranslate.app.theme"
private let defaultConfigSchemaVersion = 80

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!
    private var isObservingSharedSettings = false
    private var isShowingSettingsPage = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = true
#endif

        let controller = self.webView.configuration.userContentController
        controller.add(self, name: "controller")
        controller.add(self, name: "sharedSettings")
        // Needed so the settings page can load ES modules from file://.
        self.webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        loadAppPage()

        startObservingSharedSettingsChanges()
    }

    deinit {
        stopObservingSharedSettingsChanges()
    }

    private func loadAppPage() {
        // Prefer the bundled options-app settings UI. Falls back to Main.html
        // until the coordinator adds the `settings` folder reference to pbxproj.
        if let settingsURL = Bundle.main.url(forResource: "options-app", withExtension: "html", subdirectory: "settings") {
            isShowingSettingsPage = true
            let accessRoot = settingsURL.deletingLastPathComponent()
            self.webView.loadFileURL(settingsURL, allowingReadAccessTo: accessRoot)
            return
        }

        isShowingSettingsPage = false
        self.webView.loadFileURL(
            Bundle.main.url(forResource: "Main", withExtension: "html")!,
            allowingReadAccessTo: Bundle.main.resourceURL!
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isShowingSettingsPage {
            return
        }
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
#elseif os(macOS)
        webView.evaluateJavaScript("show('mac')")

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), false)")
                }
            }
        }
#endif
        pushSharedStatusToPage()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "controller" {
            handleControllerMessage(message.body)
            return
        }
        if message.name == "sharedSettings" {
            handleSharedSettingsMessage(message.body)
        }
    }

    private func handleControllerMessage(_ body: Any) {
#if os(macOS)
        guard let text = body as? String, text == "open-preferences" else { return }
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                NSApp.terminate(self)
            }
        }
#endif
    }

    private func handleSharedSettingsMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }

        switch type {
        case "status":
            pushSharedStatusToPage()
        case "get":
            pushSharedConfigToPage()
        case "setTargetLanguage":
            guard let code = dict["targetCode"] as? String else { return }
            applyTargetLanguage(code)
        case "setConfig":
            guard let config = dict["config"] as? [String: Any] else { return }
            let schemaVersion = (dict["schemaVersion"] as? Int)
                ?? (dict["schemaVersion"] as? NSNumber)?.intValue
                ?? defaultConfigSchemaVersion
            let ts = Date().timeIntervalSince1970 * 1000
            let result = SharedSettingsStore.shared.write(
                config: config,
                schemaVersion: schemaVersion,
                lastModifiedAt: ts,
                source: "app",
                rejectIfOlder: false
            )
            notifyPage(result: [
                "type": "setResult",
                "ok": result.ok,
                "error": result.reason as Any,
                "lastModifiedAt": ts,
            ])
            pushSharedStatusToPage()
            if result.ok {
                pushStorageChanged(key: "config", value: config)
            }
        case "storage.get":
            handleStorageGet(dict)
        case "storage.set":
            handleStorageSet(dict)
        case "storage.setMeta":
            handleStorageSetMeta(dict)
        default:
            break
        }
    }

    private func applyTargetLanguage(_ code: String) {
        var config: [String: Any]
        var schemaVersion = defaultConfigSchemaVersion
        if let envelope = SharedSettingsStore.shared.readEnvelope() {
            config = envelope.config
            schemaVersion = envelope.meta.schemaVersion > 0 ? envelope.meta.schemaVersion : defaultConfigSchemaVersion
        } else {
            // Minimal seed if extension has not migrated yet — extension sync will reconcile.
            config = [
                "language": [
                    "sourceCode": "auto",
                    "targetCode": code,
                ],
            ]
        }
        var language = (config["language"] as? [String: Any]) ?? [:]
        language["targetCode"] = code
        config["language"] = language
        let ts = Date().timeIntervalSince1970 * 1000
        let result = SharedSettingsStore.shared.write(
            config: config,
            schemaVersion: schemaVersion,
            lastModifiedAt: ts,
            source: "app",
            rejectIfOlder: false
        )
        notifyPage(result: [
            "type": "setTargetLanguageResult",
            "ok": result.ok,
            "error": result.reason as Any,
            "targetCode": code,
            "lastModifiedAt": ts,
        ])
        pushSharedStatusToPage()
        pushSharedConfigToPage()
        if result.ok {
            pushStorageChanged(key: "config", value: config)
        }
    }

    private func handleStorageGet(_ dict: [String: Any]) {
        let requestId = storageRequestId(dict)
        let key = dict["key"] as? String ?? ""
        switch key {
        case "config":
            if let envelope = SharedSettingsStore.shared.readEnvelope() {
                replyStorageResult(requestId: requestId, ok: true, value: envelope.config)
            } else if SharedSettingsStore.shared.isAvailable {
                replyStorageResult(requestId: requestId, ok: true)
            } else {
                replyStorageResult(requestId: requestId, ok: false, error: "app_group_unavailable")
            }
        case "theme":
            if let theme = UserDefaults.standard.string(forKey: appThemeDefaultsKey) {
                replyStorageResult(requestId: requestId, ok: true, value: theme)
            } else {
                replyStorageResult(requestId: requestId, ok: true)
            }
        default:
            replyStorageResult(requestId: requestId, ok: false, error: "unsupported_key")
        }
    }

    private func handleStorageSet(_ dict: [String: Any]) {
        let requestId = storageRequestId(dict)
        let key = dict["key"] as? String ?? ""
        switch key {
        case "config":
            guard let config = dict["value"] as? [String: Any] else {
                replyStorageResult(requestId: requestId, ok: false, error: "missing_config")
                return
            }
            let schemaVersion = schemaVersionForWrite(dict)
            let ts = Date().timeIntervalSince1970 * 1000
            let result = SharedSettingsStore.shared.write(
                config: config,
                schemaVersion: schemaVersion,
                lastModifiedAt: ts,
                source: "app",
                rejectIfOlder: false
            )
            if result.ok {
                replyStorageResult(requestId: requestId, ok: true, value: config)
                pushStorageChanged(key: "config", value: config)
                pushSharedStatusToPage()
            } else {
                replyStorageResult(requestId: requestId, ok: false, error: result.reason ?? "write_failed")
            }
        case "theme":
            guard let theme = dict["value"] as? String else {
                replyStorageResult(requestId: requestId, ok: false, error: "missing_theme")
                return
            }
            UserDefaults.standard.set(theme, forKey: appThemeDefaultsKey)
            replyStorageResult(requestId: requestId, ok: true, value: theme)
            pushStorageChanged(key: "theme", value: theme)
        default:
            replyStorageResult(requestId: requestId, ok: false, error: "unsupported_key")
        }
    }

    private func handleStorageSetMeta(_ dict: [String: Any]) {
        let requestId = storageRequestId(dict)
        let key = dict["key"] as? String ?? ""
        let meta = dict["meta"] as? [String: Any] ?? [:]
        switch key {
        case "config":
            guard let envelope = SharedSettingsStore.shared.readEnvelope() else {
                // Nothing to stamp yet (get/set will create the envelope).
                replyStorageResult(requestId: requestId, ok: true)
                return
            }
            let lastModifiedAt = (meta["lastModifiedAt"] as? Double)
                ?? (meta["lastModifiedAt"] as? NSNumber)?.doubleValue
                ?? envelope.meta.lastModifiedAt
            let schemaVersion = envelope.meta.schemaVersion > 0
                ? envelope.meta.schemaVersion
                : defaultConfigSchemaVersion
            let result = SharedSettingsStore.shared.write(
                config: envelope.config,
                schemaVersion: schemaVersion,
                lastModifiedAt: lastModifiedAt,
                source: envelope.meta.source ?? "app",
                rejectIfOlder: false
            )
            if result.ok {
                replyStorageResult(requestId: requestId, ok: true)
            } else {
                replyStorageResult(requestId: requestId, ok: false, error: result.reason ?? "write_failed")
            }
        case "theme":
            replyStorageResult(requestId: requestId, ok: true)
        default:
            replyStorageResult(requestId: requestId, ok: false, error: "unsupported_key")
        }
    }

    private func storageRequestId(_ dict: [String: Any]) -> String? {
        if let value = dict["requestId"] as? String {
            return value
        }
        if let value = dict["requestId"] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private func schemaVersionForWrite(_ dict: [String: Any]) -> Int {
        if let value = dict["schemaVersion"] as? Int {
            return value
        }
        if let value = dict["schemaVersion"] as? NSNumber {
            return value.intValue
        }
        if let envelope = SharedSettingsStore.shared.readEnvelope(), envelope.meta.schemaVersion > 0 {
            return envelope.meta.schemaVersion
        }
        return defaultConfigSchemaVersion
    }

    private func replyStorageResult(requestId: String?, ok: Bool, value: Any? = nil, error: String? = nil) {
        var payload: [String: Any] = [
            "type": "storage.result",
            "ok": ok,
        ]
        if let requestId {
            payload["requestId"] = requestId
        }
        if let value {
            payload["value"] = value
        }
        if let error {
            payload["error"] = error
        }
        notifyPage(result: payload)
    }

    private func pushStorageChanged(key: String, value: Any?) {
        var payload: [String: Any] = [
            "type": "storage.changed",
            "key": key,
        ]
        if let value {
            payload["value"] = value
        }
        notifyPage(result: payload)
    }

    private func startObservingSharedSettingsChanges() {
        guard !isObservingSharedSettings else { return }
        isObservingSharedSettings = true
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<ViewController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.handleSharedSettingsChangedExternally()
                }
            },
            SharedSettingsKeys.darwinNotifyName,
            nil,
            .deliverImmediately
        )
    }

    private func stopObservingSharedSettingsChanges() {
        guard isObservingSharedSettings else { return }
        isObservingSharedSettings = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(SharedSettingsKeys.darwinNotifyName),
            nil
        )
    }

    /// Pushes `storage.changed` when the App Group blob changes (including writes from the extension).
    private func handleSharedSettingsChangedExternally() {
        if let envelope = SharedSettingsStore.shared.readEnvelope() {
            pushStorageChanged(key: "config", value: envelope.config)
        }
        pushSharedStatusToPage()
    }

    private func pushSharedStatusToPage() {
        let store = SharedSettingsStore.shared
        var payload: [String: Any] = [
            "type": "status",
            "appGroupAvailable": store.isAvailable,
            "migrated": store.hasCompletedMigration,
            "appGroupId": SharedSettingsKeys.appGroupId,
        ]
        if let envelope = store.readEnvelope() {
            payload["hasConfig"] = true
            payload["schemaVersion"] = envelope.meta.schemaVersion
            payload["lastModifiedAt"] = envelope.meta.lastModifiedAt
            payload["source"] = envelope.meta.source as Any
            if let language = envelope.config["language"] as? [String: Any] {
                payload["targetCode"] = language["targetCode"] as Any
                payload["sourceCode"] = language["sourceCode"] as Any
            }
        } else {
            payload["hasConfig"] = false
        }
        notifyPage(result: payload)
    }

    private func pushSharedConfigToPage() {
        var payload: [String: Any] = ["type": "config"]
        if let envelope = SharedSettingsStore.shared.readEnvelope() {
            payload["ok"] = true
            payload["config"] = envelope.config
            payload["schemaVersion"] = envelope.meta.schemaVersion
            payload["lastModifiedAt"] = envelope.meta.lastModifiedAt
            payload["source"] = envelope.meta.source as Any
        } else {
            payload["ok"] = false
            payload["error"] = SharedSettingsStore.shared.isAvailable ? "empty" : "app_group_unavailable"
        }
        notifyPage(result: payload)
    }

    private func notifyPage(result: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__onSharedSettings && window.__onSharedSettings(\(json))"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
