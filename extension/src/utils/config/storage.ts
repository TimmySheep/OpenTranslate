import type { Config } from "@/types/config/config"
import type { ConfigMeta, ConfigValueAndMeta } from "@/types/config/meta"
import { configSchema } from "@/types/config/config"
import { z } from "zod"
import { CONFIG_SCHEMA_VERSION, CONFIG_STORAGE_KEY, DEFAULT_CONFIG } from "../constants/config"
import { logger } from "../logger"
import { storageAdapter } from "../atoms/storage-adapter"

export async function getLocalConfig() {
  const config = await storageAdapter.get<Config | null>(CONFIG_STORAGE_KEY, null, z.custom<Config | null>(value => value === null || typeof value === "object"))
  if (config === null) {
    logger.warn("No config found in storage")
    return null
  }
  const parsedConfig = configSchema.safeParse(config)
  if (!parsedConfig.success) {
    logger.error("Config is invalid, using default config")
    return DEFAULT_CONFIG
  }
  return parsedConfig.data
}

export async function setLocalConfig(config: Config) {
  const parsedConfig = configSchema.safeParse(config)
  if (!parsedConfig.success) {
    throw new Error("Config is invalid")
  }
  await storageAdapter.set(CONFIG_STORAGE_KEY, parsedConfig.data, configSchema)
  await storageAdapter.setMeta(CONFIG_STORAGE_KEY, { lastModifiedAt: Date.now() })
}

export async function getLocalConfigAndMeta(): Promise<ConfigValueAndMeta> {
  try {
    const [config, meta] = await Promise.all([
      storageAdapter.get<Config | null>(CONFIG_STORAGE_KEY, null, configSchema.nullable()),
      storageAdapter.getMeta<ConfigMeta>(CONFIG_STORAGE_KEY),
    ])

    if (!config) {
      throw new Error("Local config not found")
    }

    const parsedConfig = configSchema.safeParse(config)
    if (!parsedConfig.success) {
      throw new Error("Local config is invalid")
    }

    return {
      value: parsedConfig.data,
      meta: {
        schemaVersion: meta?.schemaVersion ?? CONFIG_SCHEMA_VERSION,
        lastModifiedAt: meta?.lastModifiedAt ?? Date.now(),
      },
    }
  }
  catch (error) {
    logger.error("Failed to get local config", error)
    throw error
  }
}

export async function setLocalConfigAndMeta(config: Config, meta: Partial<ConfigMeta>) {
  const lastModifiedAt = meta.lastModifiedAt ?? Date.now()
  const parsedConfig = configSchema.safeParse(config)
  if (!parsedConfig.success) {
    throw new Error("Config is invalid")
  }
  await storageAdapter.set(CONFIG_STORAGE_KEY, parsedConfig.data, configSchema)
  await storageAdapter.setMeta(CONFIG_STORAGE_KEY, { ...meta, lastModifiedAt })
}
