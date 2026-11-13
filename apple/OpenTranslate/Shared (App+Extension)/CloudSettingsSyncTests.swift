//
//  CloudSettingsSyncTests.swift
//  Command-line proofs for the iCloud whitelist filter.
//  Not part of the app/extension targets (see project.pbxproj).
//
//  Run:
//    swiftc -parse-as-library -o /tmp/CloudSettingsSyncTests \
//      "CloudSettingsSync.swift" "CloudSettingsSyncTests.swift" && /tmp/CloudSettingsSyncTests
//

import Foundation

@main
enum CloudSettingsSyncTests {
    static func main() {
        var failed = 0
        failed += check("keeps language codes and display mode") { try keepLanguageAndMode() }
        failed += check("keeps theme and fontSize when present") { try keepThemeAndFontSize() }
        failed += check("drops language.level and all non-whitelist fields") { try dropsNonWhitelist() }
        failed += check("API key never enters the payload") { try apiKeyNeverEntersPayload() }
        failed += check("token/secret/queue fields never enter the payload") { try secretsAndQueueNeverEnter() }
        failed += check("deeply nested apiKey is not copied even if under a allowed parent") { try nestedAPIKeyNotCopied() }
        failed += check("empty extract yields no payload") { try emptyExtractIsNil() }
        failed += check("payloadContainsAPIKey is false for a clean payload") { try detectorClean() }

        if failed == 0 {
            print("CloudSettingsSyncTests: all 8 passed")
            exit(0)
        } else {
            print("CloudSettingsSyncTests: \(failed) failed")
            exit(1)
        }
    }

    private static func check(_ name: String, _ body: () throws -> Void) -> Int {
        do {
            try body()
            print("PASS  \(name)")
            return 0
        } catch {
            print("FAIL  \(name): \(error)")
            return 1
        }
    }

    private struct TestError: Error, CustomStringConvertible {
        let description: String
    }

    private static func fail(_ message: String) throws -> Never {
        throw TestError(description: message)
    }

    private static func sampleConfig() -> [String: Any] {
        [
            "language": [
                "sourceCode": "auto",
                "targetCode": "zho",
                "level": "intermediate",
            ],
            "translate": [
                "providerId": "openai-default",
                "mode": "bilingual",
                "requestQueueConfig": [
                    "capacity": 60,
                    "rate": 10,
                ],
                "page": [
                    "preload": [
                        "margin": 800,
                        "threshold": 0.5,
                    ],
                ],
            ],
            "theme": "dark",
            "fontSize": 16,
            "providersConfig": [
                [
                    "id": "openai-default",
                    "name": "OpenAI",
                    "provider": "openai",
                    "enabled": true,
                    "apiKey": "sk-THIS-MUST-NOT-SYNC",
                    "baseURL": "https://api.openai.com/v1",
                ],
                [
                    "id": "custom",
                    "name": "Custom",
                    "provider": "openai-compatible",
                    "enabled": true,
                    "apiKey": "secret-token-xyz",
                    "headers": [
                        "authorization": "Bearer secret-token-xyz",
                    ],
                ],
            ],
            "account": [
                "userId": "user-123",
                "billingPlan": "pro",
            ],
            "deviceId": "deadbeef-device",
        ]
    }

    private static func keepLanguageAndMode() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: sampleConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000
        ) else {
            try fail("expected a payload")
        }
        let language = payload.config["language"] as? [String: Any]
        let translate = payload.config["translate"] as? [String: Any]
        guard language?["sourceCode"] as? String == "auto" else { try fail("sourceCode missing") }
        guard language?["targetCode"] as? String == "zho" else { try fail("targetCode missing") }
        guard translate?["mode"] as? String == "bilingual" else { try fail("mode missing") }
        guard payload.schemaVersion == 80, payload.lastModifiedAt == 1000 else {
            try fail("meta not copied")
        }
    }

    private static func keepThemeAndFontSize() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: sampleConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000
        ) else {
            try fail("expected a payload")
        }
        guard payload.config["theme"] as? String == "dark" else { try fail("theme missing") }
        guard payload.config["fontSize"] as? Int == 16 else { try fail("fontSize missing") }
    }

    private static func dropsNonWhitelist() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: sampleConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000
        ) else {
            try fail("expected a payload")
        }
        let language = payload.config["language"] as? [String: Any] ?? [:]
        if language["level"] != nil { try fail("language.level must not sync") }
        let translate = payload.config["translate"] as? [String: Any] ?? [:]
        if translate["providerId"] != nil { try fail("translate.providerId must not sync") }
        if translate["requestQueueConfig"] != nil { try fail("queue config must not sync") }
        if payload.config["providersConfig"] != nil { try fail("providersConfig must not sync") }
        if payload.config["account"] != nil { try fail("account must not sync") }
        if payload.config["deviceId"] != nil { try fail("deviceId must not sync") }
    }

    private static func apiKeyNeverEntersPayload() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: sampleConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000
        ) else {
            try fail("expected a payload")
        }
        let json = payload.jsonObject()
        let blob = try String(data: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), encoding: .utf8) ?? ""
        print("PAYLOAD  \(blob)")
        if blob.contains("sk-THIS-MUST-NOT-SYNC") {
            try fail("API key value leaked into payload JSON")
        }
        if blob.lowercased().contains("apikey") {
            try fail("apiKey key leaked into payload JSON: \(blob)")
        }
        if CloudSettingsSync.payloadContainsAPIKey(payload) {
            try fail("payloadContainsAPIKey should be false")
        }
        if CloudSettingsSync.containsForbiddenKeys(payload.config) {
            try fail("containsForbiddenKeys should be false for filtered config")
        }
    }

    private static func secretsAndQueueNeverEnter() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: sampleConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000
        ) else {
            try fail("expected a payload")
        }
        let blob = try String(data: payload.jsonData(), encoding: .utf8) ?? ""
        for needle in ["secret-token-xyz", "Bearer", "user-123", "deadbeef-device", "capacity", "billingPlan"] {
            if blob.contains(needle) {
                try fail("forbidden value \(needle) leaked: \(blob)")
            }
        }
    }

    private static func nestedAPIKeyNotCopied() throws {
        // Even if a future typo tried to whitelist a parent object, extractAllowedFields
        // only copies leaf paths, so providersConfig.apiKey cannot ride along.
        let config: [String: Any] = [
            "language": ["sourceCode": "eng", "targetCode": "zho"],
            "providersConfig": [["apiKey": "sk-nested"]],
        ]
        guard let payload = CloudSettingsSync.makePayload(from: config, schemaVersion: 1, lastModifiedAt: 1) else {
            try fail("expected a payload")
        }
        let blob = try String(data: payload.jsonData(), encoding: .utf8) ?? ""
        if blob.contains("sk-nested") || blob.contains("providersConfig") {
            try fail("nested apiKey or providersConfig leaked: \(blob)")
        }
    }

    private static func emptyExtractIsNil() throws {
        let config: [String: Any] = [
            "providersConfig": [["apiKey": "sk-only-secret"]],
            "account": ["userId": "abc"],
        ]
        if CloudSettingsSync.makePayload(from: config, schemaVersion: 1, lastModifiedAt: 1) != nil {
            try fail("payload should be nil when no whitelist fields exist")
        }
    }

    private static func detectorClean() throws {
        guard let payload = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "eng", "targetCode": "zho"], "translate": ["mode": "translationOnly"]],
            schemaVersion: 80,
            lastModifiedAt: 2
        ) else {
            try fail("expected a payload")
        }
        if CloudSettingsSync.payloadContainsAPIKey(payload) {
            try fail("clean payload flagged as containing API key")
        }
    }
}
