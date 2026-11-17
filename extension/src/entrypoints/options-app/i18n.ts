import { catalog, defaultLocale } from "virtual:app-locales"
import { createStaticI18n } from "./static-i18n"

/**
 * Must be imported before any module that calls `i18n.t()` at load time.
 * Installs a `browser.i18n.getMessage` polyfill backed by bundled `_locales`.
 */
const language = typeof navigator === "undefined" ? defaultLocale : navigator.language
createStaticI18n({ catalog, defaultLocale, language }).install()
