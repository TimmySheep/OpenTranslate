export {
  getSharedSettings,
  getSharedSettingsStatus,
  isSafariRuntime,
  markSharedSettingsMigrated,
  setSharedSettings,
} from "./native-bridge"
export {
  pushLocalConfigToShared,
  syncSharedSettingsWithAppGroup,
} from "./sync"
export type { SyncOutcome } from "./sync"
