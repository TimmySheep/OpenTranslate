/**
 * Safari-only bridge to the native SafariWebExtensionHandler.
 * Uses browser.runtime.sendNativeMessage. Safe no-op stubs on other browsers.
 */

import { browser } from "#imports"
import { IS_SAFARI } from "@/utils/browser-env"

export type SharedSettingsStatus = {
  ok: boolean
  appGroupAvailable?: boolean
  migrated?: boolean
  hasConfig?: boolean
  schemaVersion?: number
  lastModifiedAt?: number
  source?: string | null
  appGroupId?: string
  error?: string
}

export type SharedSettingsGetResult = SharedSettingsStatus & {
  config?: Record<string, unknown>
}

export function isSafariRuntime(): boolean {
  return IS_SAFARI
}

async function sendNative<T extends Record<string, unknown>>(message: Record<string, unknown>): Promise<T> {
  if (!IS_SAFARI) {
    return { ok: false, error: "not_safari" } as unknown as T
  }
  if (typeof browser.runtime.sendNativeMessage !== "function") {
    return { ok: false, error: "sendNativeMessage_unavailable" } as unknown as T
  }
  // Safari ignores application id; pass a placeholder.
  const response = await browser.runtime.sendNativeMessage("net.timhuang.opentranslate", message)
  return (response ?? { ok: false, error: "empty_response" }) as T
}

export async function getSharedSettingsStatus(): Promise<SharedSettingsStatus> {
  return sendNative<SharedSettingsStatus>({ type: "sharedSettings.status" })
}

export async function getSharedSettings(): Promise<SharedSettingsGetResult> {
  return sendNative<SharedSettingsGetResult>({ type: "sharedSettings.get" })
}

export async function setSharedSettings(params: {
  config: Record<string, unknown>
  schemaVersion: number
  lastModifiedAt: number
  source?: string
  rejectIfOlder?: boolean
}): Promise<SharedSettingsStatus> {
  return sendNative<SharedSettingsStatus>({
    type: "sharedSettings.set",
    config: params.config,
    schemaVersion: params.schemaVersion,
    lastModifiedAt: params.lastModifiedAt,
    source: params.source ?? "extension",
    rejectIfOlder: params.rejectIfOlder ?? true,
  })
}

export async function markSharedSettingsMigrated(): Promise<SharedSettingsStatus> {
  return sendNative<SharedSettingsStatus>({ type: "sharedSettings.markMigrated" })
}
