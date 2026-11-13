import type { ZodSchema } from "zod"
import { storage } from "#imports"
import { isNonNullish } from "@/utils/utils"

export type StorageAdapter = {
  get: <T>(key: string, fallback: T, schema: ZodSchema<T>) => Promise<T>
  set: <T>(key: string, value: T, schema: ZodSchema<T>) => Promise<void>
  setMeta: (key: string, meta: Record<string, unknown>) => Promise<void>
  watch: <T>(key: string, callback: (newValue: T) => void) => () => void
}

/**
 * Default WXT `browser.storage.local` adapter.
 * Behavior must stay identical to the pre-extraction implementation.
 */
export function createWxtStorageAdapter(): StorageAdapter {
  return {
    async get<T>(key: string, fallback: T, schema: ZodSchema<T>): Promise<T> {
      const value = await storage.getItem<T>(`local:${key}`)
      if (isNonNullish(value)) {
        const parsedValue = schema.safeParse(value)
        if (parsedValue.success) {
          return parsedValue.data
        }
      }
      return fallback
    },
    async set<T>(key: string, value: T, schema: ZodSchema<T>) {
      const parsedValue = schema.safeParse(value)
      if (parsedValue.success) {
        await storage.setItem(`local:${key}`, parsedValue.data)
      }
      else {
        throw new Error(parsedValue.error.message)
      }
    },
    async setMeta(key: string, meta: Record<string, unknown>) {
      await storage.setMeta(`local:${key}`, meta)
    },
    watch<T>(key: string, callback: (newValue: T) => void) {
      const unwatch = storage.watch<T>(`local:${key}`, (newValue) => {
        if (isNonNullish(newValue))
          callback(newValue)
      })
      return unwatch
    },
  }
}

let currentAdapter: StorageAdapter = createWxtStorageAdapter()

export function getStorageAdapter(): StorageAdapter {
  return currentAdapter
}

export function setStorageAdapter(adapter: StorageAdapter) {
  currentAdapter = adapter
}

export function resetStorageAdapter() {
  currentAdapter = createWxtStorageAdapter()
}

/**
 * Mutable facade so existing `import { storageAdapter }` call sites keep working.
 * App entrypoints can call `setStorageAdapter(createBridgeAdapter())` before atoms mount.
 */
export const storageAdapter: StorageAdapter = {
  get: (key, fallback, schema) => currentAdapter.get(key, fallback, schema),
  set: (key, value, schema) => currentAdapter.set(key, value, schema),
  setMeta: (key, meta) => currentAdapter.setMeta(key, meta),
  watch: (key, callback) => currentAdapter.watch(key, callback),
}

export const STORAGE_BRIDGE = {
  get: "storage.get",
  set: "storage.set",
  setMeta: "storage.setMeta",
  result: "storage.result",
  changed: "storage.changed",
} as const

export type StorageBridgePort = {
  postMessage: (message: Record<string, unknown>) => void
  subscribe: (listener: (payload: Record<string, unknown>) => void) => () => void
}

export type CreateBridgeAdapterOptions = {
  port?: StorageBridgePort
  timeoutMs?: number
}

type SharedSettingsHandler = (payload: Record<string, unknown>) => void

const defaultBridgeListeners = new Set<SharedSettingsHandler>()
let defaultBridgePatched = false

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null
}

function getSharedSettingsHandler(): { postMessage: (message: Record<string, unknown>) => void } | undefined {
  const webkit = (globalThis as { window?: { webkit?: { messageHandlers?: { sharedSettings?: { postMessage: (message: Record<string, unknown>) => void } } } } }).window?.webkit
    ?? (globalThis as { webkit?: { messageHandlers?: { sharedSettings?: { postMessage: (message: Record<string, unknown>) => void } } } }).webkit
  return webkit?.messageHandlers?.sharedSettings
}

function patchOnSharedSettings() {
  const target = (globalThis as { window?: Window & { __onSharedSettings?: SharedSettingsHandler } }).window
    ?? (globalThis as unknown as Window & { __onSharedSettings?: SharedSettingsHandler })
  if (defaultBridgePatched || typeof target !== "object" || target === null)
    return
  defaultBridgePatched = true

  let downstream = target.__onSharedSettings
  const hooked: SharedSettingsHandler = (payload) => {
    if (typeof downstream === "function")
      downstream(payload)
    for (const listener of defaultBridgeListeners)
      listener(payload)
  }

  Object.defineProperty(target, "__onSharedSettings", {
    configurable: true,
    enumerable: true,
    get: () => hooked,
    set: (fn: SharedSettingsHandler | undefined) => {
      downstream = fn
    },
  })
}

/** Test-only: allow re-patching after jsdom window resets. */
export function resetDefaultBridgePort() {
  defaultBridgePatched = false
  defaultBridgeListeners.clear()
}

export function createDefaultWebKitPort(): StorageBridgePort {
  return {
    postMessage(message) {
      const handler = getSharedSettingsHandler()
      if (!handler || typeof handler.postMessage !== "function") {
        throw new Error("WKWebView sharedSettings message handler is unavailable")
      }
      handler.postMessage(message)
    },
    subscribe(listener) {
      patchOnSharedSettings()
      defaultBridgeListeners.add(listener)
      return () => {
        defaultBridgeListeners.delete(listener)
      }
    },
  }
}

type PendingRequest = {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
  timer: ReturnType<typeof setTimeout>
}

/**
 * Storage adapter that talks to the companion app over the WKWebView message bridge.
 *
 * JS → native (`webkit.messageHandlers.sharedSettings.postMessage`):
 *   `{ type: "storage.get"|"storage.set"|"storage.setMeta", requestId, key, value?, meta? }`
 *
 * Native → JS (`window.__onSharedSettings`):
 *   `{ type: "storage.result", requestId, ok, value?, error? }`
 *   `{ type: "storage.changed", key, value }`
 *
 * Existing sharedSettings message types are forwarded to any previous
 * `__onSharedSettings` handler and must stay backward compatible.
 */
export function createBridgeAdapter(options: CreateBridgeAdapterOptions = {}): StorageAdapter {
  const port = options.port ?? createDefaultWebKitPort()
  const timeoutMs = options.timeoutMs ?? 5000
  let requestSeq = 0
  const pending = new Map<string, PendingRequest>()
  const watchers = new Map<string, Set<(value: never) => void>>()

  port.subscribe((payload) => {
    if (payload.type === STORAGE_BRIDGE.result) {
      const requestId = payload.requestId
      if (typeof requestId !== "string")
        return
      const request = pending.get(requestId)
      if (!request)
        return
      clearTimeout(request.timer)
      pending.delete(requestId)
      if (payload.ok === true) {
        request.resolve(payload.value)
      }
      else {
        request.reject(new Error(typeof payload.error === "string" ? payload.error : "storage bridge error"))
      }
      return
    }

    if (payload.type === STORAGE_BRIDGE.changed) {
      if (typeof payload.key !== "string")
        return
      const listeners = watchers.get(payload.key)
      if (!listeners)
        return
      for (const listener of listeners)
        listener(payload.value as never)
    }
  })

  function send(message: Record<string, unknown>): Promise<unknown> {
    const requestId = String(++requestSeq)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(requestId)
        reject(new Error(`storage bridge timeout: ${String(message.type)}`))
      }, timeoutMs)
      pending.set(requestId, { resolve, reject, timer })
      try {
        port.postMessage({ ...message, requestId })
      }
      catch (error) {
        clearTimeout(timer)
        pending.delete(requestId)
        reject(error instanceof Error ? error : new Error(String(error)))
      }
    })
  }

  return {
    async get<T>(key: string, fallback: T, schema: ZodSchema<T>): Promise<T> {
      try {
        const value = await send({ type: STORAGE_BRIDGE.get, key })
        if (isNonNullish(value)) {
          const parsedValue = schema.safeParse(value)
          if (parsedValue.success) {
            return parsedValue.data
          }
        }
      }
      catch {
        // Match WXT get(): missing / invalid / transport failure → fallback
      }
      return fallback
    },
    async set<T>(key: string, value: T, schema: ZodSchema<T>) {
      const parsedValue = schema.safeParse(value)
      if (parsedValue.success) {
        await send({ type: STORAGE_BRIDGE.set, key, value: parsedValue.data })
      }
      else {
        throw new Error(parsedValue.error.message)
      }
    },
    async setMeta(key: string, meta: Record<string, unknown>) {
      await send({ type: STORAGE_BRIDGE.setMeta, key, meta })
    },
    watch<T>(key: string, callback: (newValue: T) => void) {
      let listeners = watchers.get(key)
      if (!listeners) {
        listeners = new Set()
        watchers.set(key, listeners)
      }
      listeners.add(callback as (value: never) => void)
      return () => {
        listeners?.delete(callback as (value: never) => void)
        if (listeners?.size === 0)
          watchers.delete(key)
      }
    },
  }
}
