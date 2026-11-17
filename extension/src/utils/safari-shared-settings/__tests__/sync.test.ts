import { beforeEach, describe, expect, it, vi } from "vitest"

const getSharedSettingsStatus = vi.fn()
const getSharedSettings = vi.fn()
const setSharedSettings = vi.fn()
const markSharedSettingsMigrated = vi.fn()
const isSafariRuntime = vi.fn(() => true)

vi.mock("../native-bridge", () => ({
  getSharedSettingsStatus,
  getSharedSettings,
  setSharedSettings,
  markSharedSettingsMigrated,
  isSafariRuntime,
}))

const getItem = vi.fn()
const getMeta = vi.fn()
const setItem = vi.fn()
const setMeta = vi.fn()

const storageMock = {
  getItem,
  getMeta,
  setItem,
  setMeta,
}

// WxtVitest rewrites `import { storage } from "#imports"` to wxt/utils/storage,
// so both targets must be mocked (same pattern as config/__tests__/init.test.ts).
vi.mock("#imports", () => ({
  storage: storageMock,
}))

vi.mock("wxt/utils/storage", () => ({
  storage: storageMock,
}))

describe("syncSharedSettingsWithAppGroup", () => {
  let DEFAULT_CONFIG: Record<string, unknown>

  beforeEach(async () => {
    vi.resetModules()
    vi.clearAllMocks()
    isSafariRuntime.mockReturnValue(true)
    getSharedSettingsStatus.mockResolvedValue({ ok: true, appGroupAvailable: true })
    markSharedSettingsMigrated.mockResolvedValue({ ok: true })
    setItem.mockResolvedValue(undefined)
    setMeta.mockResolvedValue(undefined)
    const mod = await import("@/utils/constants/config")
    DEFAULT_CONFIG = structuredClone(mod.DEFAULT_CONFIG) as Record<string, unknown>
  })

  it("migrates local config into empty App Group", async () => {
    getItem.mockResolvedValue(DEFAULT_CONFIG)
    getMeta.mockResolvedValue({ schemaVersion: 80, lastModifiedAt: 1000 })
    getSharedSettings.mockResolvedValue({ ok: true, hasConfig: false })
    setSharedSettings.mockResolvedValue({ ok: true })

    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()

    expect(outcome).toMatchObject({ status: "migrated_to_shared", lastModifiedAt: 1000 })
    expect(setSharedSettings).toHaveBeenCalledWith(expect.objectContaining({
      lastModifiedAt: 1000,
      source: "extension-migration",
      rejectIfOlder: false,
    }))
    expect(markSharedSettingsMigrated).toHaveBeenCalled()
  })

  it("pulls shared config when local is empty", async () => {
    getItem.mockResolvedValue(null)
    getMeta.mockResolvedValue({})
    getSharedSettings.mockResolvedValue({
      ok: true,
      hasConfig: true,
      config: DEFAULT_CONFIG,
      schemaVersion: 80,
      lastModifiedAt: 2000,
    })

    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()

    expect(outcome).toMatchObject({ status: "pulled_from_shared", lastModifiedAt: 2000 })
    expect(setItem).toHaveBeenCalled()
    expect(setMeta).toHaveBeenCalledWith("local:config", expect.objectContaining({
      lastModifiedAt: 2000,
    }))
  })

  it("lets newer shared win over older local", async () => {
    getItem.mockResolvedValue(DEFAULT_CONFIG)
    getMeta.mockResolvedValue({ schemaVersion: 80, lastModifiedAt: 1000 })
    getSharedSettings.mockResolvedValue({
      ok: true,
      hasConfig: true,
      config: DEFAULT_CONFIG,
      schemaVersion: 80,
      lastModifiedAt: 3000,
    })

    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()

    expect(outcome).toMatchObject({ status: "pulled_from_shared", lastModifiedAt: 3000 })
    expect(setItem).toHaveBeenCalled()
    expect(setSharedSettings).not.toHaveBeenCalled()
  })

  it("pushes newer local over older shared", async () => {
    getItem.mockResolvedValue(DEFAULT_CONFIG)
    getMeta.mockResolvedValue({ schemaVersion: 80, lastModifiedAt: 5000 })
    getSharedSettings.mockResolvedValue({
      ok: true,
      hasConfig: true,
      config: DEFAULT_CONFIG,
      schemaVersion: 80,
      lastModifiedAt: 1000,
    })
    setSharedSettings.mockResolvedValue({ ok: true })

    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()

    expect(outcome).toMatchObject({ status: "pushed_to_shared", lastModifiedAt: 5000 })
    expect(setSharedSettings).toHaveBeenCalledWith(expect.objectContaining({
      lastModifiedAt: 5000,
      source: "extension",
    }))
  })

  it("skips when not safari", async () => {
    isSafariRuntime.mockReturnValue(false)
    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()
    expect(outcome).toEqual({ status: "skipped", reason: "not_safari" })
  })

  it("errors when app group unavailable", async () => {
    getSharedSettingsStatus.mockResolvedValue({ ok: true, appGroupAvailable: false })
    const { syncSharedSettingsWithAppGroup } = await import("../sync")
    const outcome = await syncSharedSettingsWithAppGroup()
    expect(outcome.status).toBe("error")
  })
})
