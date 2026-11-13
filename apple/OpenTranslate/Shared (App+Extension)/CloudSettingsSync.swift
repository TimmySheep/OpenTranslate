//
//  CloudSettingsSync.swift
//  Shared between the containing app and Safari web extension native handler.
//
//  Whitelist filter, payload assembly, and lastModifiedAt merge for a
//  lightweight iCloud overlay. The App Group JSON shape is never rewritten
//  wholesale: only allowed preference paths are copied in or out.
//
//  Red line: never copy the full config. Secrets (apiKey, token, secret, …)
//  must not enter an iCloud payload, and inbound payloads are re-filtered
//  before being applied onto local state.
//

import Foundation

protocol CloudKeyValueStoring: AnyObject {
    var isAvailable: Bool { get }
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// Default KVS backend. Unavailable when the user is not signed into iCloud.
final class UbiquitousCloudKeyValueStore: CloudKeyValueStoring {
    static let shared = UbiquitousCloudKeyValueStore()

    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func data(forKey key: String) -> Data? {
        guard isAvailable else { return nil }
        return NSUbiquitousKeyValueStore.default.data(forKey: key)
    }

    func set(_ data: Data?, forKey key: String) {
        guard isAvailable else { return }
        let store = NSUbiquitousKeyValueStore.default
        if let data {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
        store.synchronize()
    }
}

enum CloudSettingsKeys {
    /// Independent of App Group key names (`opentranslate.config.json` / `.meta`).
    static let payload = "opentranslate.icloud.settings.v1"
}

enum CloudMergeResult: Equatable {
    case pushedToCloud
    case pulledFromCloud
    case inSync
    case skipped(reason: String)
}

enum CloudSettingsSync {
    /// Preference paths allowed in an iCloud payload (dot paths from config root).
    /// Everything else is dropped, including `language.level` and all provider fields.
    static let allowedPaths: [String] = [
        "language.sourceCode",
        "language.targetCode",
        "translate.mode",
        "theme",
        "fontSize",
    ]

    /// Keys that must never appear anywhere in a payload, even if a typo lands on the whitelist.
    static let forbiddenKeyFragments: [String] = [
        "apiKey",
        "apikey",
        "api_key",
        "accessToken",
        "access_token",
        "refreshToken",
        "secret",
        "password",
        "authorization",
        "sessionToken",
        "privateKey",
    ]

    struct Payload: Equatable {
        var schemaVersion: Int
        var lastModifiedAt: Double
        var config: [String: Any]

        static func == (lhs: Payload, rhs: Payload) -> Bool {
            lhs.schemaVersion == rhs.schemaVersion
                && lhs.lastModifiedAt == rhs.lastModifiedAt
                && NSDictionary(dictionary: lhs.config).isEqual(to: rhs.config)
        }

        func jsonObject() -> [String: Any] {
            [
                "schemaVersion": schemaVersion,
                "lastModifiedAt": lastModifiedAt,
                "config": config,
            ]
        }

        func jsonData() throws -> Data {
            try JSONSerialization.data(withJSONObject: jsonObject(), options: [.sortedKeys])
        }
    }

    /// Builds an iCloud-bound payload from a local App Group config blob.
    /// Returns nil when the whitelist extract is empty.
    static func makePayload(
        from config: [String: Any],
        schemaVersion: Int,
        lastModifiedAt: Double
    ) -> Payload? {
        let filtered = extractAllowedFields(from: config)
        guard !filtered.isEmpty else { return nil }
        precondition(
            !containsForbiddenKeys(filtered),
            "CloudSettingsSync produced a payload containing a forbidden secret key"
        )
        return Payload(schemaVersion: schemaVersion, lastModifiedAt: lastModifiedAt, config: filtered)
    }

    /// Copies only `allowedPaths` out of `config`, preserving nested object shape.
    static func extractAllowedFields(from config: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for path in allowedPaths {
            if let value = value(at: path, in: config) {
                setValue(value, at: path, into: &result)
            }
        }
        return result
    }

    /// Overlays whitelisted fields from `cloudConfig` onto a full local config,
    /// leaving secrets and every other local key untouched.
    static func applyCloudFields(_ cloudConfig: [String: Any], onto local: [String: Any]) -> [String: Any] {
        var result = local
        let allowed = extractAllowedFields(from: cloudConfig)
        for path in allowedPaths {
            if let value = value(at: path, in: allowed) {
                setValue(value, at: path, into: &result)
            }
        }
        return result
    }

    static func containsForbiddenKeys(_ value: Any) -> Bool {
        switch value {
        case let dict as [String: Any]:
            for (key, child) in dict {
                if isForbiddenKey(key) { return true }
                if containsForbiddenKeys(child) { return true }
            }
            return false
        case let array as [Any]:
            return array.contains { containsForbiddenKeys($0) }
        default:
            return false
        }
    }

    static func payloadContainsAPIKey(_ payload: Payload) -> Bool {
        containsForbiddenKeys(payload.jsonObject())
    }

    // MARK: - Store I/O

    static func readPayload(from store: CloudKeyValueStoring) -> Payload? {
        guard store.isAvailable, let data = store.data(forKey: CloudSettingsKeys.payload) else {
            return nil
        }
        return parsePayload(from: data)
    }

    /// Re-filters inbound JSON so a tainted cloud blob cannot inject secrets.
    static func parsePayload(from data: Data) -> Payload? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let schemaVersion = intValue(json["schemaVersion"]),
              let lastModifiedAt = doubleValue(json["lastModifiedAt"]),
              let config = json["config"] as? [String: Any] else {
            return nil
        }
        let filtered = extractAllowedFields(from: config)
        guard !filtered.isEmpty, !containsForbiddenKeys(filtered) else { return nil }
        return Payload(schemaVersion: schemaVersion, lastModifiedAt: lastModifiedAt, config: filtered)
    }

    /// Mirrors the whitelist extract of `config` into iCloud. No-op when KVS is
    /// unavailable or when the extract is empty. Always filters before writing.
    @discardableResult
    static func push(
        config: [String: Any],
        schemaVersion: Int,
        lastModifiedAt: Double,
        to store: CloudKeyValueStoring
    ) -> Bool {
        guard store.isAvailable else { return false }
        guard let payload = makePayload(from: config, schemaVersion: schemaVersion, lastModifiedAt: lastModifiedAt) else {
            return false
        }
        guard let data = try? payload.jsonData() else { return false }
        store.set(data, forKey: CloudSettingsKeys.payload)
        return true
    }

    /// lastModifiedAt last-write-wins. iCloud wins when strictly newer.
    /// Returns the config/meta that should live in the App Group afterwards.
    static func merge(
        local: (config: [String: Any], meta: SharedConfigMeta)?,
        store: CloudKeyValueStoring
    ) -> (result: CloudMergeResult, config: [String: Any]?, meta: SharedConfigMeta?) {
        guard store.isAvailable else {
            return (.skipped(reason: "icloud_unavailable"), local?.config, local?.meta)
        }

        let remote = readPayload(from: store)

        guard let local else {
            guard let remote else {
                return (.skipped(reason: "both_empty"), nil, nil)
            }
            let meta = SharedConfigMeta(
                schemaVersion: remote.schemaVersion,
                lastModifiedAt: remote.lastModifiedAt,
                source: "icloud"
            )
            return (.pulledFromCloud, remote.config, meta)
        }

        guard let remote else {
            let pushed = push(
                config: local.config,
                schemaVersion: local.meta.schemaVersion,
                lastModifiedAt: local.meta.lastModifiedAt,
                to: store
            )
            return (pushed ? .pushedToCloud : .skipped(reason: "nothing_to_push"), local.config, local.meta)
        }

        if remote.lastModifiedAt > local.meta.lastModifiedAt {
            let merged = applyCloudFields(remote.config, onto: local.config)
            let meta = SharedConfigMeta(
                schemaVersion: local.meta.schemaVersion,
                lastModifiedAt: remote.lastModifiedAt,
                source: "icloud"
            )
            return (.pulledFromCloud, merged, meta)
        }

        if local.meta.lastModifiedAt > remote.lastModifiedAt {
            let pushed = push(
                config: local.config,
                schemaVersion: local.meta.schemaVersion,
                lastModifiedAt: local.meta.lastModifiedAt,
                to: store
            )
            return (pushed ? .pushedToCloud : .inSync, local.config, local.meta)
        }

        return (.inSync, local.config, local.meta)
    }

    // MARK: - Path helpers

    private static func isForbiddenKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return forbiddenKeyFragments.contains { fragment in
            lowered == fragment.lowercased() || lowered.contains(fragment.lowercased())
        }
    }

    private static func value(at path: String, in object: [String: Any]) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = object
        for part in parts {
            guard let dict = current as? [String: Any], let next = dict[part] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func setValue(_ value: Any, at path: String, into object: inout [String: Any]) {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return }
        if parts.count == 1 {
            object[first] = value
            return
        }
        var child = object[first] as? [String: Any] ?? [:]
        setValue(value, at: parts.dropFirst().joined(separator: "."), into: &child)
        object[first] = child
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
