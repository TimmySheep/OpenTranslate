let appSettingsMode = false

/** Turn on App settings UI mode. Only call this from the options-app entrypoint. */
export function enableAppSettingsMode() {
  appSettingsMode = true
}

export function resetAppSettingsMode() {
  appSettingsMode = false
}

/** True when the shared options UI is running inside the native App WKWebView. */
export function isAppSettingsMode() {
  return appSettingsMode
}
