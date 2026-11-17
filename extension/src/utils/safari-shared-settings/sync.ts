/**
 * Bidirectional sync between extension browser.storage.local (local:config)
 * and the App Group store exposed by the native handler.
 *
 * Conflict policy (same device): higher lastModifiedAt wins.
 * Migration: if App Group empty and extension has config, push once and mark migrated.
 * Never logs API key values.
 */

import type { Config } from "@/types/config/config"
import { storage } from "#imports"
import { configSchema } from "@/types/config/config"
import { CONFIG_SCHEMA_VERSION, CONFIG_STORAGE_KEY, DEFAULT_CONFIG } from "@/utils/constants/config"
import { logger } from "@/utils/logger"
import {
  getSharedSettings,
  getSharedSettingsStatus,
  isSafariRuntime,
  markSharedSettingsMigrated,
  setSharedSettings,
} from "./native-bridge"

export type SyncOutcome =
  | { status: "skipped"; reason: string }
  | { status: "migrated_to_shared"; lastModifiedAt: number }
  | { status: "pulled_from_shared"; lastModifiedAt: number }
  | { status: "pushed_to_shared"; lastModifiedAt: number }
  | { status: "in_sync"; lastModifiedAt: number }
  | { status: "error"; reason: string }

type ConfigMeta = {
  schemaVersion?: number
  lastModifiedAt?: number
}

async function readLocal(): Promise<{ config: Config | null, meta: ConfigMeta }> {
  const [raw, meta] = await Promise.all([
    storage.getItem<Config>(`local:${CONFIG_STORAGE_KEY}`),
    storage.getMeta<ConfigMeta>(`local:${CONFIG_STORAGE_KEY}`),
  ])
  if (!raw) {
    return { config: null, meta: meta ?? {} }
  }
  const parsed = configSchema.safeParse(raw)
  if (!parsed.success) {
    logger.warn("safari-shared-settings: local config invalid during sync")
    return { config: null, meta: meta ?? {} }
  }
  return { config: parsed.data, meta: meta ?? {} }
}

async function writeLocal(config: Config, meta: ConfigMeta): Promise<void> {
  await storage.setItem<Config>(`local:${CONFIG_STORAGE_KEY}`, config)
  await storage.setMeta<ConfigMeta>(`local:${CONFIG_STORAGE_KEY}`, {
    schemaVersion: meta.schemaVersion ?? CONFIG_SCHEMA_VERSION,
    lastModifiedAt: meta.lastModifiedAt ?? Date.now(),
  })
}

/**
 * Run after initializeConfig(). Safe to call repeatedly.
 */
export async function syncSharedSettingsWithAppGroup(depth = 0): Promise<SyncOutcome> {
  if (!isSafariRuntime()) {
    return { status: "skipped", reason: "not_safari" }
  }

  const status = await getSharedSettingsStatus()
  if (!status.ok || status.appGroupAvailable === false) {
    return { status: "error", reason: status.error ?? "app_group_unavailable" }
  }

  const local = await readLocal()
  const shared = await getSharedSettings()

  if (!shared.ok) {
    return { status: "error", reason: shared.error ?? "shared_get_failed" }
  }

  const localTs = local.meta.lastModifiedAt ?? 0
  const sharedTs = shared.lastModifiedAt ?? 0
  const hasLocal = !!local.config
  const hasShared = !!shared.hasConfig && !!shared.config

  // First-run migration: extension has data, shared empty
  if (hasLocal && !hasShared) {
    const ts = localTs || Date.now()
    const push = await setSharedSettings({
      config: local.config as unknown as Record<string, unknown>,
      schemaVersion: local.meta.schemaVersion ?? CONFIG_SCHEMA_VERSION,
      lastModifiedAt: ts,
      source: "extension-migration",
      rejectIfOlder: false,
    })
    if (!push.ok) {
      return { status: "error", reason: push.error ?? "migration_push_failed" }
    }
    await markSharedSettingsMigrated()
    return { status: "migrated_to_shared", lastModifiedAt: ts }
  }

  // New install / empty local, shared has data — never overwrite shared with defaults
  if (!hasLocal && hasShared) {
    const parsed = configSchema.safeParse(shared.config)
    if (!parsed.success) {
      return { status: "error", reason: "shared_config_invalid" }
    }
    await writeLocal(parsed.data, {
      schemaVersion: shared.schemaVersion ?? CONFIG_SCHEMA_VERSION,
      lastModifiedAt: sharedTs || Date.now(),
    })
    await markSharedSettingsMigrated()
    return { status: "pulled_from_shared", lastModifiedAt: sharedTs }
  }

  if (!hasLocal && !hasShared) {
    // Ensure defaults exist locally without clobbering a future cloud pull.
    await writeLocal(DEFAULT_CONFIG, {
      schemaVersion: CONFIG_SCHEMA_VERSION,
      lastModifiedAt: Date.now(),
    })
    return { status: "skipped", reason: "both_empty_seeded_local_only" }
  }

  // Both present — lastModifiedAt wins
  if (sharedTs > localTs && hasShared) {
    const parsed = configSchema.safeParse(shared.config)
    if (!parsed.success) {
      return { status: "error", reason: "shared_config_invalid" }
    }
    await writeLocal(parsed.data, {
      schemaVersion: shared.schemaVersion ?? CONFIG_SCHEMA_VERSION,
      lastModifiedAt: sharedTs,
    })
    return { status: "pulled_from_shared", lastModifiedAt: sharedTs }
  }

  if (localTs > sharedTs && hasLocal) {
    const push = await setSharedSettings({
      config: local.config as unknown as Record<string, unknown>,
      schemaVersion: local.meta.schemaVersion ?? CONFIG_SCHEMA_VERSION,
      lastModifiedAt: localTs,
      source: "extension",
      rejectIfOlder: true,
    })
    if (!push.ok) {
      if (push.error === "stale_write") {
        if (depth >= 2) {
          return { status: "error", reason: "stale_write_retry_exhausted" }
        }
        return syncSharedSettingsWithAppGroup(depth + 1)
      }
      return { status: "error", reason: push.error ?? "push_failed" }
    }
    return { status: "pushed_to_shared", lastModifiedAt: localTs }
  }

  return { status: "in_sync", lastModifiedAt: localTs }
}

/**
 * Push current local config to App Group after a successful local write.
 */
export async function pushLocalConfigToShared(config: Config, lastModifiedAt: number): Promise<SyncOutcome> {
  if (!isSafariRuntime()) {
    return { status: "skipped", reason: "not_safari" }
  }
  const push = await setSharedSettings({
    config: config as unknown as Record<string, unknown>,
    schemaVersion: CONFIG_SCHEMA_VERSION,
    lastModifiedAt,
    source: "extension",
    rejectIfOlder: true,
  })
  if (!push.ok) {
    return { status: "error", reason: push.error ?? "push_failed" }
  }
  return { status: "pushed_to_shared", lastModifiedAt }
}
