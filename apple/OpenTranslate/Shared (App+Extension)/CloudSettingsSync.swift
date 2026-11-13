//
//  CloudSettingsSync.swift
//  Shared between the containing app and Safari web extension native handler.
//
//  Whitelist filter + iCloud KVS payload assembly. This file is pure logic:
//  it does not talk to NSUbiquitousKeyValueStore yet.
//
//  Red line: never copy the full config. Only explicitly listed preference
//  paths may enter an iCloud payload. Secrets (apiKey, token, secret, …)
//  and everything else stay out.
//

import Foundation

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
}
