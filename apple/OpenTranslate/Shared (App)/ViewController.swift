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

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = true
#endif

        let controller = self.webView.configuration.userContentController
        controller.add(self, name: "controller")
        controller.add(self, name: "sharedSettings")

        self.webView.loadFileURL(
            Bundle.main.url(forResource: "Main", withExtension: "html")!,
            allowingReadAccessTo: Bundle.main.resourceURL!
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
                ?? 80
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
        default:
            break
        }
    }

    private func applyTargetLanguage(_ code: String) {
        var config: [String: Any]
        var schemaVersion = 80
        if let envelope = SharedSettingsStore.shared.readEnvelope() {
            config = envelope.config
            schemaVersion = envelope.meta.schemaVersion > 0 ? envelope.meta.schemaVersion : 80
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
