//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Native bridge for same-device shared settings via App Group.
//  Message protocol (JSON object in SFExtensionMessageKey):
//    { "type": "sharedSettings.get" }
//    { "type": "sharedSettings.set", "config": {...}, "schemaVersion": N, "lastModifiedAt": ms, "source": "extension" }
//    { "type": "sharedSettings.status" }
//    { "type": "sharedSettings.markMigrated" }
//  Responses always include "ok": bool; never echo API key material into logs.
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let log = Logger(subsystem: "net.timhuang.opentranslate", category: "NativeBridge")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        // Log type only — never the full payload (may contain secrets until Keychain split).
        let typeName = (message as? [String: Any])?["type"] as? String ?? "unknown"
        log.log("Native message type=\(typeName, privacy: .public) profile=\(profile?.uuidString ?? "none", privacy: .public)")

        let responsePayload = handle(message: message, profile: profile)

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responsePayload]
        } else {
            response.userInfo = ["message": responsePayload]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func handle(message: Any?, profile: UUID?) -> [String: Any] {
        // Profile-scoped storage is intentionally NOT used for shared settings:
        // product goal is one config per Apple device install. Documented limitation.
        _ = profile

        guard let dict = message as? [String: Any], let type = dict["type"] as? String else {
            return ["ok": false, "error": "invalid_message"]
        }

        switch type {
        case "sharedSettings.status":
            return statusResponse()
        case "sharedSettings.get":
            return getResponse()
        case "sharedSettings.set":
            return setResponse(dict)
        case "sharedSettings.markMigrated":
            SharedSettingsStore.shared.markMigrationCompleted()
            return ["ok": true]
        case "ping":
            return ["ok": true, "echo": "pong"]
        default:
            return ["ok": false, "error": "unknown_type", "type": type]
        }
    }

    private func statusResponse() -> [String: Any] {
        let store = SharedSettingsStore.shared
        var result: [String: Any] = [
            "ok": true,
            "appGroupAvailable": store.isAvailable,
            "migrated": store.hasCompletedMigration,
            "appGroupId": SharedSettingsKeys.appGroupId,
        ]
        if let envelope = store.readEnvelope() {
            result["hasConfig"] = true
            result["schemaVersion"] = envelope.meta.schemaVersion
            result["lastModifiedAt"] = envelope.meta.lastModifiedAt
            result["source"] = envelope.meta.source as Any
        } else {
            result["hasConfig"] = false
        }
        return result
    }

    private func getResponse() -> [String: Any] {
        let store = SharedSettingsStore.shared
        guard store.isAvailable else {
            return ["ok": false, "error": "app_group_unavailable"]
        }
        guard let envelope = store.readEnvelope() else {
            return [
                "ok": true,
                "hasConfig": false,
                "migrated": store.hasCompletedMigration,
            ]
        }
        return [
            "ok": true,
            "hasConfig": true,
            "config": envelope.config,
            "schemaVersion": envelope.meta.schemaVersion,
            "lastModifiedAt": envelope.meta.lastModifiedAt,
            "source": envelope.meta.source as Any,
            "migrated": store.hasCompletedMigration,
        ]
    }

    private func setResponse(_ dict: [String: Any]) -> [String: Any] {
        let store = SharedSettingsStore.shared
        guard store.isAvailable else {
            return ["ok": false, "error": "app_group_unavailable"]
        }
        guard let config = dict["config"] as? [String: Any] else {
            return ["ok": false, "error": "missing_config"]
        }
        let schemaVersion = (dict["schemaVersion"] as? Int)
            ?? (dict["schemaVersion"] as? NSNumber)?.intValue
            ?? 0
        let lastModifiedAt = (dict["lastModifiedAt"] as? Double)
            ?? (dict["lastModifiedAt"] as? NSNumber)?.doubleValue
            ?? Date().timeIntervalSince1970 * 1000
        let source = dict["source"] as? String ?? "extension"
        let rejectIfOlder = (dict["rejectIfOlder"] as? Bool) ?? true

        let result = store.write(
            config: config,
            schemaVersion: schemaVersion,
            lastModifiedAt: lastModifiedAt,
            source: source,
            rejectIfOlder: rejectIfOlder
        )
        if result.ok {
            return [
                "ok": true,
                "schemaVersion": schemaVersion,
                "lastModifiedAt": lastModifiedAt,
            ]
        }
        return ["ok": false, "error": result.reason ?? "write_failed"]
    }
}
