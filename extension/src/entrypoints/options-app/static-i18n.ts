export type ChromeMessage = {
  message: string
}

export type LocaleCatalog = Record<string, Record<string, ChromeMessage>>

export type StaticI18nOptions = {
  catalog: LocaleCatalog
  defaultLocale: string
  language: string
}

/**
 * Map a BCP 47 tag (e.g. zh-Hans-CN, en-US) onto a Chrome `_locales` folder name.
 */
export function resolveLocale(available: string[], preferred: string, fallback: string): string {
  if (available.length === 0)
    return fallback

  const byLower = new Map(available.map(locale => [locale.toLowerCase(), locale]))
  const normalized = preferred.replaceAll("-", "_")
  const exact = byLower.get(normalized.toLowerCase())
  if (exact)
    return exact

  const parts = normalized.split("_").filter(Boolean)
  const lang = parts[0]
  const region = parts.length >= 2 ? parts[parts.length - 1] : undefined
  if (lang && region && region.length === 2) {
    const withRegion = byLower.get(`${lang}_${region}`.toLowerCase())
    if (withRegion)
      return withRegion
  }
  if (lang) {
    const langOnly = byLower.get(lang.toLowerCase())
    if (langOnly)
      return langOnly
    const prefix = available.find(locale => locale.toLowerCase().startsWith(`${lang.toLowerCase()}_`))
    if (prefix)
      return prefix
  }
  return byLower.get(fallback.toLowerCase()) ?? fallback
}

function substitute(template: string, substitutions?: string | string[]): string {
  if (substitutions == null)
    return template
  const values = Array.isArray(substitutions) ? substitutions : [substitutions]
  return template.replace(/\$(\d)/g, (match, digit: string) => {
    const index = Number(digit) - 1
    return index >= 0 && index < values.length ? String(values[index]) : match
  })
}

export function createStaticI18n(options: StaticI18nOptions) {
  const available = Object.keys(options.catalog)
  const locale = resolveLocale(available, options.language, options.defaultLocale)
  const fallbackTable = options.catalog[options.defaultLocale] ?? {}
  const table = options.catalog[locale] ?? fallbackTable

  function getMessage(key: string, substitutions?: string | string[]): string {
    const entry = table[key] ?? fallbackTable[key]
    if (!entry?.message)
      return ""
    return substitute(entry.message, substitutions)
  }

  function getUILanguage(): string {
    return options.language
  }

  function install(target: typeof globalThis = globalThis) {
    const i18n = { getMessage, getUILanguage }
    const runtime = { id: "opentranslate-app" }
    const current = target as typeof globalThis & {
      browser?: { runtime?: { id?: string }, i18n?: unknown }
      chrome?: { runtime?: { id?: string }, i18n?: unknown }
    }
    current.browser = { ...current.browser, runtime: { ...current.browser?.runtime, ...runtime }, i18n }
    current.chrome = { ...current.chrome, runtime: { ...current.chrome?.runtime, ...runtime }, i18n }
  }

  return { locale, getMessage, getUILanguage, install }
}
