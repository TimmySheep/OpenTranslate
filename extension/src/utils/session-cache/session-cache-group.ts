import type { ProxyResponse } from "@/types/proxy-fetch"
import { z } from "zod"
import { DEFAULT_PROXY_CACHE_TTL_MS } from "@/utils/constants/proxy-fetch"
import { logger } from "@/utils/logger"
import { storageAdapter } from "@/utils/atoms/storage-adapter"

const anySchema = z.custom<unknown>(() => true)
const keysSchema = z.array(z.string())

interface CacheMetadata extends Record<string, unknown> {
  timestamp: number
}

type CachedItem = ProxyResponse

// TODO: solve race condition of cache group registry
export class SessionCache {
  private prefix: string
  private keysListKey: `session:${string}`
  private isInitialized = false

  constructor(groupKey: string = "default") {
    this.prefix = `cache_${groupKey}`
    this.keysListKey = `session:${this.prefix}__meta_keys` as const
  }

  private makeKey(reqMethod: string, targetUrl: string) {
    return `session:${this.prefix}_${reqMethod.toUpperCase()}_${targetUrl}` as const
  }

  private async ensureKeysListInitialized(): Promise<void> {
    if (this.isInitialized)
      return

    const existing = await storageAdapter.get<string[] | null>(this.keysListKey, null, keysSchema.nullable())
    if (existing === null) {
      await storageAdapter.set(this.keysListKey, [], keysSchema)
    }
    this.isInitialized = true
  }

  async get(reqMethod: string, targetUrl: string, ttl: number = DEFAULT_PROXY_CACHE_TTL_MS): Promise<ProxyResponse | undefined> {
    try {
      const key = this.makeKey(reqMethod, targetUrl)
      const [item, metadata] = await Promise.all([
        storageAdapter.get<CachedItem | null>(key, null, anySchema as z.ZodType<CachedItem | null>),
        storageAdapter.getMeta<CacheMetadata>(key),
      ])

      if (!item || !metadata) {
        return undefined
      }

      if (Date.now() - metadata.timestamp > ttl) {
        await this.delete(reqMethod, targetUrl)
        return undefined
      }

      logger.info("[SessionCache] Cache hit:", { reqMethod, targetUrl })
      return item
    }
    catch (error) {
      logger.error("[SessionCache] Get error:", error)
      return undefined
    }
  }

  async set(reqMethod: string, targetUrl: string, response: ProxyResponse): Promise<void> {
    try {
      await this.ensureKeysListInitialized()

      const key = this.makeKey(reqMethod, targetUrl)
      const now = Date.now()

      // Set cache item and metadata in parallel
      await Promise.all([
        storageAdapter.set(key, response, anySchema as z.ZodType<CachedItem>),
        storageAdapter.setMeta(key, {
          timestamp: now,
        }),
      ])

      // Track this key for group clearing
      const keysList = await storageAdapter.get<string[]>(this.keysListKey, [], keysSchema)
      if (!keysList.includes(key)) {
        keysList.push(key)
        await storageAdapter.set(this.keysListKey, keysList, keysSchema)
      }

      logger.info("[SessionCache] Cache set:", { reqMethod, targetUrl })
    }
    catch (error) {
      logger.error("[SessionCache] Set error:", error)
    }
  }

  async delete(reqMethod: string, targetUrl: string): Promise<void> {
    try {
      await this.ensureKeysListInitialized()

      const key = this.makeKey(reqMethod, targetUrl)

      // Remove both data and metadata in parallel
      await Promise.all([
        storageAdapter.remove(key, true),
      ])

      // Remove from keys list
      const keysList = await storageAdapter.get<string[]>(this.keysListKey, [], keysSchema)
      const updatedKeysList = keysList.filter(k => k !== key)
      await storageAdapter.set(this.keysListKey, updatedKeysList, keysSchema)
    }
    catch (error) {
      logger.error("[SessionCache] Delete error:", error)
    }
  }

  async clear(): Promise<void> {
    try {
      await this.ensureKeysListInitialized()

      // Get all tracked keys for this group
      const keysList = await storageAdapter.get<string[]>(this.keysListKey, [], keysSchema)

      if (keysList.length > 0) {
        // Use bulk removal for better performance
        await storageAdapter.removeMany(keysList)
      }

      // Clear the keys list itself
      await storageAdapter.remove(this.keysListKey)
      this.isInitialized = false // Reset initialization flag

      logger.info("[SessionCache] Cleared cache:", { count: keysList.length })
    }
    catch (error) {
      logger.error("[SessionCache] Clear error:", error)
    }
  }
}
