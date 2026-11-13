//
//  SharedSettingsStore.swift
//  Shared between the containing app and Safari web extension native handler.
//
//  Same-device source of truth for OpenTranslate settings (JSON blob).
//  Requires App Group entitlement (pending Developer portal approval):
//    group.net.timhuang.opentranslate
//
//  API keys currently may still ride inside the JSON until Keychain separation
//  lands; do not log this blob. Cloud sync strips secrets via CloudSettingsSync
//  before any iCloud write. iCloud is an overlay: newer lastModifiedAt wins,
//  and only whitelisted preference fields are applied onto the local blob.
//  When iCloud / KVS is unavailable, behavior matches the local-only store.
//

import Foundation
import os.log

enum SharedSettingsKeys {
    static let appGroupId = "group.net.timhuang.opentranslate"
    static let configJSON = "opentranslate.config.json"
    static let configMeta = "opentranslate.config.meta"
    static let migrationFlag = "opentranslate.migratedFromExtensionStorage.v1"
    static let darwinNotifyName = "net.timhuang.opentranslate.settingsChanged" as CFString
}

struct SharedConfigMeta: Codable, Equatable {
    var schemaVersion: Int
    var lastModifiedAt: Double
    var source: String?
}

final class SharedSettingsStore {
    static let shared = SharedSettingsStore()
    private let log = Logger(subsystem: "net.timhuang.opentranslate", category: "SharedSettings")
    private let defaultsOverride: UserDefaults?
    private let cloudStore: CloudKeyValueStoring
    private var didMergeFromCloud = false

    init(
        defaults: UserDefaults? = nil,
        cloudStore: CloudKeyValueStoring = UbiquitousCloudKeyValueStore.shared
    ) {
        self.defaultsOverride = defaults
        self.cloudStore = cloudStore
    }

    private var defaults: UserDefaults? {
        defaultsOverride ?? UserDefaults(suiteName: SharedSettingsKeys.appGroupId)
    }

    var isAvailable: Bool {
        defaults != nil
    }

    func readEnvelope() -> (config: [String: Any], meta: SharedConfigMeta)? {
        mergeFromCloudIfNeeded()
        return readEnvelopeRaw()
    }

    /// Writes shared config. Uses lastModifiedAt to refuse stale overwrites when `rejectIfOlder` is true.
    /// After a successful local write, the whitelist extract is mirrored to iCloud when available.
    @discardableResult
    func write(
        config: [String: Any],
        schemaVersion: Int,
        lastModifiedAt: Double,
        source: String,
        rejectIfOlder: Bool = true,
        mirrorToCloud: Bool = true
    ) -> (ok: Bool, reason: String?) {
        guard let defaults else {
            return (false, "app_group_unavailable")
        }
        if rejectIfOlder, let existing = readEnvelopeRaw() {
            if lastModifiedAt < existing.meta.lastModifiedAt {
                return (false, "stale_write")
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
            let meta = SharedConfigMeta(schemaVersion: schemaVersion, lastModifiedAt: lastModifiedAt, source: source)
            let metaData = try JSONEncoder().encode(meta)
            defaults.set(data, forKey: SharedSettingsKeys.configJSON)
            defaults.set(metaData, forKey: SharedSettingsKeys.configMeta)
            defaults.synchronize()
            if mirrorToCloud {
                CloudSettingsSync.push(
                    config: config,
                    schemaVersion: schemaVersion,
                    lastModifiedAt: lastModifiedAt,
                    to: cloudStore
                )
            }
            postChangeNotification()
            return (true, nil)
        } catch {
            log.error("Failed to write shared config: \(String(describing: error))")
            return (false, "encode_failed")
        }
    }

    /// Startup / first-read merge. iCloud (strictly newer) wins over the App Group
    /// for whitelisted fields only. Silent no-op when KVS is unavailable.
    @discardableResult
    func mergeFromCloudIfNeeded() -> CloudMergeResult {
        if didMergeFromCloud {
            return .skipped(reason: "already_merged")
        }
        didMergeFromCloud = true
        let outcome = CloudSettingsSync.merge(local: readEnvelopeRaw(), store: cloudStore)
        if outcome.result == .pulledFromCloud, let config = outcome.config, let meta = outcome.meta {
            write(
                config: config,
                schemaVersion: meta.schemaVersion,
                lastModifiedAt: meta.lastModifiedAt,
                source: meta.source ?? "icloud",
                rejectIfOlder: false,
                mirrorToCloud: false
            )
        }
        return outcome.result
    }

    var hasCompletedMigration: Bool {
        defaults?.bool(forKey: SharedSettingsKeys.migrationFlag) ?? false
    }

    func markMigrationCompleted() {
        defaults?.set(true, forKey: SharedSettingsKeys.migrationFlag)
        defaults?.synchronize()
    }

    private func readEnvelopeRaw() -> (config: [String: Any], meta: SharedConfigMeta)? {
        guard let defaults else {
            log.error("App Group UserDefaults unavailable — entitlement likely missing")
            return nil
        }
        guard let data = defaults.data(forKey: SharedSettingsKeys.configJSON) else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            guard let dict = json as? [String: Any] else { return nil }
            let metaData = defaults.data(forKey: SharedSettingsKeys.configMeta)
            let meta: SharedConfigMeta
            if let metaData,
               let decoded = try? JSONDecoder().decode(SharedConfigMeta.self, from: metaData) {
                meta = decoded
            } else {
                meta = SharedConfigMeta(schemaVersion: 0, lastModifiedAt: 0, source: nil)
            }
            return (dict, meta)
        } catch {
            log.error("Failed to decode shared config: \(String(describing: error))")
            return nil
        }
    }

    private func postChangeNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(SharedSettingsKeys.darwinNotifyName),
            nil,
            nil,
            true
        )
    }
    /// Test-only: inspect App Group state without triggering a cloud merge.
    func readEnvelopeRawForTests() -> (config: [String: Any], meta: SharedConfigMeta)? {
        readEnvelopeRaw()
    }

}
