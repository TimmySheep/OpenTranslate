import { afterEach, describe, expect, it, vi } from "vitest"
import { enableAppSettingsMode, isAppSettingsMode, resetAppSettingsMode } from "../app-settings-mode"

afterEach(() => {
  resetAppSettingsMode()
  vi.restoreAllMocks()
})

describe("app settings capability gating", () => {
  it("is off by default so the Safari options page still sends messages", () => {
    expect(isAppSettingsMode()).toBe(false)
    const sendMessage = vi.fn()
    if (!isAppSettingsMode())
      sendMessage("setTranslateRequestQueueConfig", { rate: 1 })
    expect(sendMessage).toHaveBeenCalledOnce()
  })

  it("hides the translation-hub link and clear-cache action in App mode", async () => {
    enableAppSettingsMode()
    const { ToolsNav } = await import("@/entrypoints/options/app-sidebar/tools-nav")
    const { ClearCacheConfig } = await import("@/entrypoints/options/pages/translation/clear-cache-config")
    expect(ToolsNav()).toBeNull()
    expect(ClearCacheConfig()).toBeNull()
  })
})
