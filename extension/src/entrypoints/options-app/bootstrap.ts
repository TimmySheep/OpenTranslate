import type { Config } from "@/types/config/config"
import type { ThemeMode } from "@/types/config/theme"
import { configSchema } from "@/types/config/config"
import { DEFAULT_THEME_MODE, themeModeSchema } from "@/types/config/theme"
import {
  createBridgeAdapter,
  setStorageAdapter,
  storageAdapter,
} from "@/utils/atoms/storage-adapter"
import { enableAppSettingsMode } from "@/utils/app-settings-mode"
import { CONFIG_STORAGE_KEY, DEFAULT_CONFIG, THEME_STORAGE_KEY } from "@/utils/constants/config"

/**
 * Install the WKWebView storage bridge before any settings atoms mount.
 * Must run at App entrypoint boot, not in the Safari extension options page.
 */
export function installAppStorageAdapter() {
  enableAppSettingsMode()
  setStorageAdapter(createBridgeAdapter())
}

export async function loadAppSettings(): Promise<{ config: Config, themeMode: ThemeMode }> {
  const [config, themeMode] = await Promise.all([
    storageAdapter.get(CONFIG_STORAGE_KEY, DEFAULT_CONFIG, configSchema),
    storageAdapter.get(THEME_STORAGE_KEY, DEFAULT_THEME_MODE, themeModeSchema),
  ])
  return { config, themeMode }
}
