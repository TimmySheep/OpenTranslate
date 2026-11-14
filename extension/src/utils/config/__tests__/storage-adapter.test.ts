import { afterEach, describe, expect, it, vi } from "vitest"
import { DEFAULT_CONFIG } from "@/utils/constants/config"

const wxtStorageAccess = vi.fn(() => {
  throw new Error("You must add the 'storage' permission to your manifest to use 'wxt/storage'")
})

vi.mock("#imports", () => ({
  storage: {
    getItem: wxtStorageAccess,
    setItem: wxtStorageAccess,
    getMeta: wxtStorageAccess,
    setMeta: wxtStorageAccess,
  },
}))

vi.mock("wxt/utils/storage", () => ({
  storage: {
    getItem: wxtStorageAccess,
    setItem: wxtStorageAccess,
    getMeta: wxtStorageAccess,
    setMeta: wxtStorageAccess,
  },
}))

const get = vi.fn()
const set = vi.fn().mockResolvedValue(undefined)
const getMeta = vi.fn().mockResolvedValue(null)
const setMeta = vi.fn().mockResolvedValue(undefined)
const watch = vi.fn()

vi.mock("@/utils/atoms/storage-adapter", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/utils/atoms/storage-adapter")>()
  return { ...actual }
})

describe("config storage adapter in the app environment", () => {
  afterEach(async () => {
    const { resetStorageAdapter } = await import("@/utils/atoms/storage-adapter")
    resetStorageAdapter()
    vi.clearAllMocks()
  })

  it("saves local config through the injected adapter without touching WXT storage", async () => {
    const { setStorageAdapter } = await import("@/utils/atoms/storage-adapter")
    setStorageAdapter({ get, set, getMeta, setMeta, remove: vi.fn(), removeMany: vi.fn(), watch })

    const { setLocalConfig } = await import("../storage")
    await setLocalConfig(DEFAULT_CONFIG)

    expect(set).toHaveBeenCalledWith("config", DEFAULT_CONFIG, expect.anything())
    expect(setMeta).toHaveBeenCalledWith("config", expect.objectContaining({ lastModifiedAt: expect.any(Number) }))
    expect(wxtStorageAccess).not.toHaveBeenCalled()
  })
})
