//
//  CloudSettingsSyncTests.swift
//  Command-line proofs for the iCloud whitelist filter.
//  Not part of the app/extension targets (see project.pbxproj).
//
//  Run:
//    swiftc -parse-as-library -o /tmp/CloudSettingsSyncTests \
//      "CloudSettingsSync.swift" "SharedSettingsStore.swift" "CloudSettingsSyncTests.swift" \
//      && /tmp/CloudSettingsSyncTests
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
        failed += check("push mirrors whitelist and omits API key") { try pushMirrorsWithoutAPIKey() }
        failed += check("merge pulls newer iCloud fields and keeps local API key") { try mergePullsAndPreservesSecrets() }
        failed += check("merge pushes newer local whitelist") { try mergePushesNewerLocal() }
        failed += check("inbound tainted payload is re-filtered") { try taintedInboundIsRefiltered() }
        failed += check("unavailable iCloud is a silent no-op") { try unavailableCloudIsNoop() }
        failed += check("unavailable iCloud ignores residual payload") { try unavailableCloudIgnoresResidualPayload() }
        failed += check("store write mirrors whitelist only") { try storeWriteMirrorsWhitelist() }
        failed += check("store first read pulls newer iCloud onto App Group") { try storeReadPullsNewerCloud() }
        failed += check("store write still succeeds when iCloud is down") { try storeWriteWorksWithoutCloud() }
        failed += check("store read stays local when iCloud is down") { try storeReadStaysLocalWithoutCloud() }

        if failed == 0 {
            print("CloudSettingsSyncTests: all 19 passed")
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

    // MARK: - Memory store

    private final class MemoryCloudStore: CloudKeyValueStoring {
        var available = true
        private var storage: [String: Data] = [:]

        var isAvailable: Bool { available }

        func data(forKey key: String) -> Data? {
            guard available else { return nil }
            return storage[key]
        }

        func set(_ data: Data?, forKey key: String) {
            guard available else { return }
            if let data {
                storage[key] = data
            } else {
                storage.removeValue(forKey: key)
            }
        }

        func payloadJSON() throws -> String {
            guard let data = storage[CloudSettingsKeys.payload] else { return "<empty>" }
            return String(data: data, encoding: .utf8) ?? "<binary>"
        }
    }

    private static func fullLocalConfig() -> [String: Any] {
        [
            "language": [
                "sourceCode": "auto",
                "targetCode": "zho",
                "level": "intermediate",
            ],
            "translate": [
                "providerId": "openai-default",
                "mode": "bilingual",
            ],
            "theme": "dark",
            "fontSize": 16,
            "providersConfig": [
                ["id": "openai-default", "apiKey": "sk-THIS-MUST-NOT-SYNC"],
            ],
        ]
    }

    private static func pushMirrorsWithoutAPIKey() throws {
        let store = MemoryCloudStore()
        let ok = CloudSettingsSync.push(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000,
            to: store
        )
        if !ok { try fail("push should succeed") }
        let blob = try store.payloadJSON()
        print("PUSH_PAYLOAD  \(blob)")
        if blob.contains("sk-THIS-MUST-NOT-SYNC") || blob.lowercased().contains("apikey") || blob.contains("providersConfig") {
            try fail("push leaked secrets: \(blob)")
        }
        if !blob.contains("\"targetCode\":\"zho\"") { try fail("push missing targetCode: \(blob)") }
    }

    private static func mergePullsAndPreservesSecrets() throws {
        let store = MemoryCloudStore()
        let cloud = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "eng", "targetCode": "jpn"], "translate": ["mode": "translationOnly"]],
            schemaVersion: 80,
            lastModifiedAt: 5000
        )!
        store.set(try cloud.jsonData(), forKey: CloudSettingsKeys.payload)

        let local = fullLocalConfig()
        let meta = SharedConfigMeta(schemaVersion: 80, lastModifiedAt: 1000, source: "extension")
        let outcome = CloudSettingsSync.merge(local: (local, meta), store: store)
        if outcome.result != .pulledFromCloud { try fail("expected pulledFromCloud, got \(outcome.result)") }
        let language = outcome.config?["language"] as? [String: Any] ?? [:]
        if language["targetCode"] as? String != "jpn" { try fail("targetCode not pulled") }
        if language["sourceCode"] as? String != "eng" { try fail("sourceCode not pulled") }
        if language["level"] as? String != "intermediate" { try fail("local language.level was dropped") }
        let providers = outcome.config?["providersConfig"] as? [[String: Any]]
        if providers?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("local API key was not preserved")
        }
        if (outcome.config?["translate"] as? [String: Any])?["mode"] as? String != "translationOnly" {
            try fail("mode not pulled")
        }
    }

    private static func mergePushesNewerLocal() throws {
        let store = MemoryCloudStore()
        let older = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "eng", "targetCode": "fra"]],
            schemaVersion: 80,
            lastModifiedAt: 1000
        )!
        store.set(try older.jsonData(), forKey: CloudSettingsKeys.payload)

        let outcome = CloudSettingsSync.merge(
            local: (fullLocalConfig(), SharedConfigMeta(schemaVersion: 80, lastModifiedAt: 4000, source: "app")),
            store: store
        )
        if outcome.result != .pushedToCloud { try fail("expected pushedToCloud, got \(outcome.result)") }
        let blob = try store.payloadJSON()
        if !blob.contains("\"targetCode\":\"zho\"") { try fail("cloud not updated: \(blob)") }
        if blob.contains("sk-THIS-MUST-NOT-SYNC") { try fail("push on merge leaked API key") }
    }

    private static func taintedInboundIsRefiltered() throws {
        let tainted: [String: Any] = [
            "schemaVersion": 80,
            "lastModifiedAt": 9,
            "config": [
                "language": ["sourceCode": "eng", "targetCode": "zho"],
                "providersConfig": [["apiKey": "sk-from-cloud"]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: tainted, options: [.sortedKeys])
        guard let parsed = CloudSettingsSync.parsePayload(from: data) else {
            try fail("expected parse to keep whitelist fields")
        }
        let blob = try String(data: parsed.jsonData(), encoding: .utf8) ?? ""
        if blob.contains("sk-from-cloud") || blob.contains("providersConfig") {
            try fail("tainted inbound leaked: \(blob)")
        }
        if CloudSettingsSync.payloadContainsAPIKey(parsed) {
            try fail("re-filtered payload still flagged")
        }
    }

    private static func unavailableCloudIsNoop() throws {
        let store = MemoryCloudStore()
        store.available = false
        let pushed = CloudSettingsSync.push(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1,
            to: store
        )
        if pushed { try fail("push should fail closed when iCloud is down") }
        if try store.payloadJSON() != "<empty>" { try fail("unavailable store was written") }
        let outcome = CloudSettingsSync.merge(
            local: (fullLocalConfig(), SharedConfigMeta(schemaVersion: 80, lastModifiedAt: 1, source: "app")),
            store: store
        )
        if outcome.result != .skipped(reason: "icloud_unavailable") {
            try fail("expected skipped, got \(outcome.result)")
        }
        if (outcome.config?["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("local config changed while iCloud was down")
        }
    }

    private static func makeIsolatedDefaults() -> UserDefaults {
        let suite = "net.timhuang.opentranslate.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func storeWriteMirrorsWhitelist() throws {
        let cloud = MemoryCloudStore()
        let defaults = makeIsolatedDefaults()
        let store = SharedSettingsStore(defaults: defaults, cloudStore: cloud)
        let result = store.write(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 2000,
            source: "app"
        )
        if !result.ok { try fail("write failed: \(result.reason ?? "?")") }
        let blob = try cloud.payloadJSON()
        print("STORE_PUSH_PAYLOAD  \(blob)")
        if blob.contains("sk-THIS-MUST-NOT-SYNC") || blob.lowercased().contains("apikey") {
            try fail("store write leaked API key: \(blob)")
        }
        let local = store.readEnvelopeRawForTests()
        if (local?.config["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("local App Group lost the API key")
        }
    }

    private static func storeReadPullsNewerCloud() throws {
        let cloud = MemoryCloudStore()
        let defaults = makeIsolatedDefaults()
        let writer = SharedSettingsStore(defaults: defaults, cloudStore: MemoryCloudStore())
        _ = writer.write(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000,
            source: "app",
            mirrorToCloud: false
        )
        let remote = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "deu", "targetCode": "kor"], "theme": "light"],
            schemaVersion: 80,
            lastModifiedAt: 9000
        )!
        cloud.set(try remote.jsonData(), forKey: CloudSettingsKeys.payload)

        let reader = SharedSettingsStore(defaults: defaults, cloudStore: cloud)
        guard let envelope = reader.readEnvelope() else { try fail("expected envelope after pull") }
        let language = envelope.config["language"] as? [String: Any] ?? [:]
        if language["targetCode"] as? String != "kor" { try fail("store did not pull targetCode") }
        if language["level"] as? String != "intermediate" { try fail("store dropped language.level") }
        if (envelope.config["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("pull overwrote API key")
        }
        if envelope.config["theme"] as? String != "light" { try fail("theme not pulled") }
        if envelope.meta.source != "icloud" { try fail("source should be icloud, got \(envelope.meta.source ?? "nil")") }
    }

    private static func storeWriteWorksWithoutCloud() throws {
        let cloud = MemoryCloudStore()
        cloud.available = false
        let store = SharedSettingsStore(defaults: makeIsolatedDefaults(), cloudStore: cloud)
        let result = store.write(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 3,
            source: "app"
        )
        if !result.ok { try fail("write should succeed when iCloud is down: \(result.reason ?? "?")") }
        if try cloud.payloadJSON() != "<empty>" { try fail("unavailable cloud was written") }
        guard let envelope = store.readEnvelope() else { try fail("local read failed") }
        if (envelope.config["language"] as? [String: Any])?["targetCode"] as? String != "zho" {
            try fail("local config missing after degraded write")
        }
        if (envelope.config["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("degraded write dropped the API key")
        }
    }

    private static func unavailableCloudIgnoresResidualPayload() throws {
        let store = MemoryCloudStore()
        let residual = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "deu", "targetCode": "kor"], "theme": "light"],
            schemaVersion: 80,
            lastModifiedAt: 9000
        )!
        store.set(try residual.jsonData(), forKey: CloudSettingsKeys.payload)
        let residualJSON = try store.payloadJSON()
        store.available = false

        if CloudSettingsSync.readPayload(from: store) != nil {
            try fail("readPayload should ignore residual data when iCloud is down")
        }
        let pushed = CloudSettingsSync.push(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1,
            to: store
        )
        if pushed { try fail("push should not write when iCloud is down") }
        if try store.payloadJSON() != residualJSON {
            try fail("unavailable push mutated residual payload")
        }
        let outcome = CloudSettingsSync.merge(
            local: (fullLocalConfig(), SharedConfigMeta(schemaVersion: 80, lastModifiedAt: 1, source: "app")),
            store: store
        )
        if outcome.result != .skipped(reason: "icloud_unavailable") {
            try fail("expected skipped, got \(outcome.result)")
        }
        if (outcome.config?["language"] as? [String: Any])?["targetCode"] as? String != "zho" {
            try fail("merge pulled residual cloud fields while iCloud was down")
        }
        if (outcome.config?["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("local API key changed while iCloud was down")
        }
    }

    private static func storeReadStaysLocalWithoutCloud() throws {
        let cloud = MemoryCloudStore()
        let defaults = makeIsolatedDefaults()
        let writer = SharedSettingsStore(defaults: defaults, cloudStore: MemoryCloudStore())
        _ = writer.write(
            config: fullLocalConfig(),
            schemaVersion: 80,
            lastModifiedAt: 1000,
            source: "app",
            mirrorToCloud: false
        )
        let remote = CloudSettingsSync.makePayload(
            from: ["language": ["sourceCode": "deu", "targetCode": "kor"], "theme": "light"],
            schemaVersion: 80,
            lastModifiedAt: 9000
        )!
        cloud.set(try remote.jsonData(), forKey: CloudSettingsKeys.payload)
        let residualJSON = try cloud.payloadJSON()
        cloud.available = false

        let reader = SharedSettingsStore(defaults: defaults, cloudStore: cloud)
        let merge = reader.mergeFromCloudIfNeeded()
        if merge != .skipped(reason: "icloud_unavailable") {
            try fail("expected skipped merge, got \(merge)")
        }
        guard let envelope = reader.readEnvelope() else { try fail("local read failed while iCloud was down") }
        let language = envelope.config["language"] as? [String: Any] ?? [:]
        if language["targetCode"] as? String != "zho" { try fail("unavailable read pulled targetCode") }
        if envelope.config["theme"] as? String != "dark" { try fail("unavailable read pulled theme") }
        if envelope.meta.source != "app" { try fail("source should stay app, got \(envelope.meta.source ?? "nil")") }
        if (envelope.config["providersConfig"] as? [[String: Any]])?.first?["apiKey"] as? String != "sk-THIS-MUST-NOT-SYNC" {
            try fail("unavailable read dropped the API key")
        }
        if try cloud.payloadJSON() != residualJSON {
            try fail("degraded read mutated residual cloud payload")
        }
    }
}
