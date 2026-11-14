import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { z } from "zod"

const getItem = vi.fn()
const setItem = vi.fn()
const setMeta = vi.fn()
const removeItem = vi.fn()
const removeItems = vi.fn()
const watch = vi.fn()

const storageMock = {
  getItem,
  setItem,
  setMeta,
  removeItem,
  removeItems,
  watch,
}

// WxtVitest rewrites `import { storage } from "#imports"` to wxt/utils/storage.
vi.mock("#imports", () => ({
  storage: storageMock,
}))

vi.mock("wxt/utils/storage", () => ({
  storage: storageMock,
}))

const stringSchema = z.string()
const objectSchema = z.object({ targetCode: z.string() })

async function loadAdapter() {
  return await import("../storage-adapter")
}

describe("createWxtStorageAdapter / default storageAdapter", () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
    getItem.mockResolvedValue(null)
    setItem.mockResolvedValue(undefined)
    setMeta.mockResolvedValue(undefined)
    watch.mockReturnValue(() => {})
  })

  afterEach(async () => {
    const { resetStorageAdapter } = await loadAdapter()
    resetStorageAdapter()
  })

  it("get returns parsed storage value for local:key", async () => {
    getItem.mockResolvedValue("en")
    const { storageAdapter } = await loadAdapter()
    await expect(storageAdapter.get("theme", "system", stringSchema)).resolves.toBe("en")
    expect(getItem).toHaveBeenCalledWith("local:theme")
  })

  it("get returns fallback when storage is empty or invalid", async () => {
    getItem.mockResolvedValue(null)
    const { storageAdapter } = await loadAdapter()
    await expect(storageAdapter.get("theme", "system", stringSchema)).resolves.toBe("system")

    getItem.mockResolvedValue(123)
    await expect(storageAdapter.get("theme", "system", stringSchema)).resolves.toBe("system")
  })

  it("set writes schema-validated value and throws on invalid input", async () => {
    const { storageAdapter } = await loadAdapter()
    await storageAdapter.set("theme", "dark", stringSchema)
    expect(setItem).toHaveBeenCalledWith("local:theme", "dark")

    setItem.mockClear()
    await expect(storageAdapter.set("theme", 1 as never, stringSchema)).rejects.toThrow()
    expect(setItem).not.toHaveBeenCalled()
  })

  it("setMeta and watch use the local: key prefix", async () => {
    const unwatch = vi.fn()
    watch.mockImplementation((_key: string, callback: (value: unknown) => void) => {
      callback("light")
      callback(null)
      return unwatch
    })
    const { storageAdapter } = await loadAdapter()
    await storageAdapter.setMeta("config", { lastModifiedAt: 42 })
    expect(setMeta).toHaveBeenCalledWith("local:config", { lastModifiedAt: 42 })

    const onChange = vi.fn()
    const stop = storageAdapter.watch("theme", onChange)
    expect(watch).toHaveBeenCalledWith("local:theme", expect.any(Function))
    expect(onChange).toHaveBeenCalledTimes(1)
    expect(onChange).toHaveBeenCalledWith("light")
    stop()
    expect(unwatch).toHaveBeenCalled()
  })

  it("setStorageAdapter swaps the implementation used by the facade", async () => {
    const { storageAdapter, setStorageAdapter, resetStorageAdapter } = await loadAdapter()
    const injected = {
      get: vi.fn().mockResolvedValue("injected"),
      set: vi.fn(),
      getMeta: vi.fn(),
      setMeta: vi.fn(),
      remove: vi.fn(),
      removeMany: vi.fn(),
      watch: vi.fn(),
    }
    setStorageAdapter(injected)
    await expect(storageAdapter.get("theme", "system", stringSchema)).resolves.toBe("injected")
    expect(injected.get).toHaveBeenCalled()
    expect(getItem).not.toHaveBeenCalled()

    resetStorageAdapter()
    getItem.mockResolvedValue("wxt")
    await expect(storageAdapter.get("theme", "system", stringSchema)).resolves.toBe("wxt")
    expect(getItem).toHaveBeenCalledWith("local:theme")
  })
})

describe("createBridgeAdapter", () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
  })

  function createMockPort() {
    const listeners = new Set<(payload: Record<string, unknown>) => void>()
    const postMessage = vi.fn()
    return {
      postMessage,
      subscribe: (listener: (payload: Record<string, unknown>) => void) => {
        listeners.add(listener)
        return () => listeners.delete(listener)
      },
      emit(payload: Record<string, unknown>) {
        for (const listener of listeners)
          listener(payload)
      },
    }
  }

  it("get posts storage.get and returns a schema-validated value", async () => {
    const { createBridgeAdapter, STORAGE_BRIDGE } = await loadAdapter()
    const port = createMockPort()
    port.postMessage.mockImplementation((message: Record<string, unknown>) => {
      port.emit({
        type: STORAGE_BRIDGE.result,
        requestId: message.requestId,
        ok: true,
        value: { targetCode: "jpn" },
      })
    })
    const adapter = createBridgeAdapter({ port, timeoutMs: 50 })
    await expect(adapter.get("config", { targetCode: "eng" }, objectSchema)).resolves.toEqual({ targetCode: "jpn" })
    expect(port.postMessage).toHaveBeenCalledWith({
      type: STORAGE_BRIDGE.get,
      requestId: "1",
      key: "config",
    })
  })

  it("get returns fallback on invalid value, error, or timeout", async () => {
    const { createBridgeAdapter, STORAGE_BRIDGE } = await loadAdapter()
    const port = createMockPort()
    port.postMessage.mockImplementation((message: Record<string, unknown>) => {
      if (message.key === "bad") {
        port.emit({ type: STORAGE_BRIDGE.result, requestId: message.requestId, ok: true, value: 123 })
      }
      else if (message.key === "err") {
        port.emit({ type: STORAGE_BRIDGE.result, requestId: message.requestId, ok: false, error: "native_error" })
      }
    })
    const adapter = createBridgeAdapter({ port, timeoutMs: 20 })
    await expect(adapter.get("bad", "fallback", stringSchema)).resolves.toBe("fallback")
    await expect(adapter.get("err", "fallback", stringSchema)).resolves.toBe("fallback")
    await expect(adapter.get("slow", "fallback", stringSchema)).resolves.toBe("fallback")
  })

  it("set validates before posting and throws without posting when invalid", async () => {
    const { createBridgeAdapter, STORAGE_BRIDGE } = await loadAdapter()
    const port = createMockPort()
    const adapter = createBridgeAdapter({ port, timeoutMs: 50 })
    await expect(adapter.set("theme", 1 as never, stringSchema)).rejects.toThrow()
    expect(port.postMessage).not.toHaveBeenCalled()

    port.postMessage.mockImplementation((message: Record<string, unknown>) => {
      port.emit({ type: STORAGE_BRIDGE.result, requestId: message.requestId, ok: true })
    })
    await adapter.set("theme", "dark", stringSchema)
    expect(port.postMessage).toHaveBeenCalledWith({
      type: STORAGE_BRIDGE.set,
      requestId: "1",
      key: "theme",
      value: "dark",
    })
  })

  it("setMeta posts storage.setMeta and watch fires on storage.changed", async () => {
    const { createBridgeAdapter, STORAGE_BRIDGE } = await loadAdapter()
    const port = createMockPort()
    port.postMessage.mockImplementation((message: Record<string, unknown>) => {
      port.emit({ type: STORAGE_BRIDGE.result, requestId: message.requestId, ok: true })
    })
    const adapter = createBridgeAdapter({ port, timeoutMs: 50 })
    await adapter.setMeta("config", { lastModifiedAt: 9 })
    expect(port.postMessage).toHaveBeenCalledWith({
      type: STORAGE_BRIDGE.setMeta,
      requestId: "1",
      key: "config",
      meta: { lastModifiedAt: 9 },
    })

    const onChange = vi.fn()
    const stop = adapter.watch("config", onChange)
    port.emit({ type: STORAGE_BRIDGE.changed, key: "config", value: { targetCode: "fra" } })
    port.emit({ type: STORAGE_BRIDGE.changed, key: "theme", value: "dark" })
    expect(onChange).toHaveBeenCalledTimes(1)
    expect(onChange).toHaveBeenCalledWith({ targetCode: "fra" })
    stop()
    port.emit({ type: STORAGE_BRIDGE.changed, key: "config", value: { targetCode: "deu" } })
    expect(onChange).toHaveBeenCalledTimes(1)
  })

  it("default WebKit port posts through sharedSettings and preserves prior __onSharedSettings", async () => {
    const { createBridgeAdapter, createDefaultWebKitPort, resetDefaultBridgePort, STORAGE_BRIDGE } = await loadAdapter()
    const postMessage = vi.fn()
    const previous = vi.fn()
    const windowLike = {
      webkit: { messageHandlers: { sharedSettings: { postMessage } } },
      __onSharedSettings: previous,
    }
    vi.stubGlobal("window", windowLike)
    resetDefaultBridgePort()

    const adapter = createBridgeAdapter({ port: createDefaultWebKitPort(), timeoutMs: 50 })
    const onChange = vi.fn()
    adapter.watch("theme", onChange)

    // Later page scripts can still assign their own handler.
    const pageHandler = vi.fn()
    windowLike.__onSharedSettings = pageHandler

    windowLike.__onSharedSettings({ type: STORAGE_BRIDGE.changed, key: "theme", value: "light" })
    expect(onChange).toHaveBeenCalledWith("light")
    expect(pageHandler).toHaveBeenCalled()
    expect(previous).not.toHaveBeenCalled()

    postMessage.mockImplementation((message: Record<string, unknown>) => {
      windowLike.__onSharedSettings({ type: STORAGE_BRIDGE.result, requestId: message.requestId, ok: true, value: "dark" })
    })
    await expect(adapter.get("theme", "system", stringSchema)).resolves.toBe("dark")
    expect(postMessage).toHaveBeenCalled()

    vi.unstubAllGlobals()
    resetDefaultBridgePort()
  })
})
