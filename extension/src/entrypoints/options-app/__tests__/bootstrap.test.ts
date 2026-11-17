import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { z } from "zod"
import type { StorageAdapter } from "@/utils/atoms/storage-adapter"

const getItem = vi.fn()
const setItem = vi.fn()
const setMeta = vi.fn()
const watch = vi.fn()

const storageMock = {
  getItem,
  setItem,
  setMeta,
  watch,
}

vi.mock("#imports", () => ({
  storage: storageMock,
}))

vi.mock("wxt/utils/storage", () => ({
  storage: storageMock,
}))

async function load() {
  const storage = await import("@/utils/atoms/storage-adapter")
  const bootstrap = await import("../bootstrap")
  const { DEFAULT_CONFIG } = await import("@/utils/constants/config")
  return { ...storage, ...bootstrap, DEFAULT_CONFIG }
}

describe("options-app bootstrap", () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
    getItem.mockResolvedValue(null)
    setItem.mockResolvedValue(undefined)
    setMeta.mockResolvedValue(undefined)
    watch.mockReturnValue(() => {})
  })

  afterEach(async () => {
    const { resetStorageAdapter } = await load()
    resetStorageAdapter()
  })

  it("installAppStorageAdapter routes writes through the bridge, not WXT storage", async () => {
    const { installAppStorageAdapter, storageAdapter } = await load()
    installAppStorageAdapter()
    await expect(storageAdapter.set("theme", "dark", z.string())).rejects.toThrow(
      /sharedSettings message handler is unavailable/,
    )
    expect(setItem).not.toHaveBeenCalled()
  })

  it("loadAppSettings reads config and theme from the current storage adapter", async () => {
    const { setStorageAdapter, loadAppSettings, DEFAULT_CONFIG } = await load()
    const config = {
      ...DEFAULT_CONFIG,
      language: {
        ...DEFAULT_CONFIG.language,
        targetCode: "jpn",
      },
    }
    const get = vi.fn(async <T>(key: string, fallback: T, _schema: z.ZodType<T>): Promise<T> => {
      if (key === "config")
        return config as T
      if (key === "theme")
        return "dark" as T
      return fallback
    })
    setStorageAdapter({
      get: get as StorageAdapter["get"],
      set: vi.fn(),
      getMeta: vi.fn(),
      setMeta: vi.fn(),
      remove: vi.fn(),
      removeMany: vi.fn(),
      watch: vi.fn(),
    })

    await expect(loadAppSettings()).resolves.toEqual({
      config,
      themeMode: "dark",
    })
    expect(get).toHaveBeenCalledWith("config", DEFAULT_CONFIG, expect.anything())
    expect(get).toHaveBeenCalledWith("theme", "system", expect.anything())
  })
})
