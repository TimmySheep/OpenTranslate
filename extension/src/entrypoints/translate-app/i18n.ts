import { catalog, defaultLocale } from "virtual:translate-app-locales"
import { createStaticI18n } from "../options-app/static-i18n"

const language = typeof navigator === "undefined" ? defaultLocale : navigator.language
createStaticI18n({ catalog, defaultLocale, language }).install()
