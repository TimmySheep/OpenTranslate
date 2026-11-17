import { describe, expect, it } from "vitest"
import { createStaticI18n, resolveLocale } from "../static-i18n"

const available = ["en", "es", "ja", "zh_CN", "zh_TW"]

describe("resolveLocale", () => {
  it("matches exact Chrome locale names", () => {
    expect(resolveLocale(available, "zh_CN", "en")).toBe("zh_CN")
    expect(resolveLocale(available, "en", "en")).toBe("en")
  })

  it("maps BCP 47 tags, including zh-Hans-CN, onto _locales folders", () => {
    expect(resolveLocale(available, "zh-Hans-CN", "en")).toBe("zh_CN")
    expect(resolveLocale(available, "zh-CN", "en")).toBe("zh_CN")
    expect(resolveLocale(available, "zh-TW", "en")).toBe("zh_TW")
    expect(resolveLocale(available, "en-US", "en")).toBe("en")
    expect(resolveLocale(available, "ja-JP", "en")).toBe("ja")
  })

  it("falls back to the default locale when nothing matches", () => {
    expect(resolveLocale(available, "fr-FR", "en")).toBe("en")
  })
})

describe("createStaticI18n", () => {
  const catalog = {
    en: {
      name: { message: "OpenTranslate" },
      options_apiProviders_badges_featureCount: { message: "$1 features" },
      options_apiProviders_form_providerInUseCannotDisable: { message: 'Cannot disable "$1" because it is currently used by $2 feature(s).' },
    },
    zh_CN: {
      name: { message: "OpenTranslate" },
      options_apiProviders_badges_featureCount: { message: "$1 项功能" },
    },
  }

  it("reads bundled messages and applies $1/$2 substitutions", () => {
    const i18n = createStaticI18n({ catalog, defaultLocale: "en", language: "en-US" })
    expect(i18n.locale).toBe("en")
    expect(i18n.getMessage("name")).toBe("OpenTranslate")
    expect(i18n.getMessage("options_apiProviders_badges_featureCount", ["12"])).toBe("12 features")
    expect(i18n.getMessage("options_apiProviders_form_providerInUseCannotDisable", ["OpenAI", "3"]))
      .toBe('Cannot disable "OpenAI" because it is currently used by 3 feature(s).')
  })

  it("falls back to the default locale for missing keys and returns empty string when absent", () => {
    const i18n = createStaticI18n({ catalog, defaultLocale: "en", language: "zh-CN" })
    expect(i18n.locale).toBe("zh_CN")
    expect(i18n.getMessage("options_apiProviders_badges_featureCount", "4")).toBe("4 项功能")
    expect(i18n.getMessage("options_apiProviders_form_providerInUseCannotDisable", ["OpenAI", "3"]))
      .toBe('Cannot disable "OpenAI" because it is currently used by 3 feature(s).')
    expect(i18n.getMessage("does_not_exist")).toBe("")
  })

  it("installs browser.i18n.getMessage so WXT i18n can run without the extension API", () => {
    const i18n = createStaticI18n({ catalog, defaultLocale: "en", language: "en" })
    i18n.install()
    const browser = (globalThis as typeof globalThis & { browser: { runtime: { id: string }, i18n: { getMessage: typeof i18n.getMessage } } }).browser
    expect(browser.runtime.id).toBe("opentranslate-app")
    expect(browser.i18n.getMessage("name")).toBe("OpenTranslate")
    expect(browser.i18n.getMessage("options_apiProviders_badges_featureCount", ["2"])).toBe("2 features")
  })

  it("mutates an already-captured browser object instead of replacing it", () => {
    const captured: { runtime?: { id?: string }, i18n?: { getMessage?: Function, getUILanguage?: Function } } = {
      runtime: { id: "opentranslate-app" },
      i18n: { getMessage: () => "", getUILanguage: () => "en" },
    }
    const target = { browser: captured, chrome: captured }
    const i18n = createStaticI18n({ catalog, defaultLocale: "en", language: "en" })
    i18n.install(target as unknown as typeof globalThis)
    expect(target.browser).toBe(captured)
    expect(captured.i18n?.getMessage?.("name")).toBe("OpenTranslate")
  })

  it("provides runtime.getManifest and getURL for options modules that call them at import time", () => {
    const i18n = createStaticI18n({ catalog, defaultLocale: "en", language: "en" })
    const target = {} as typeof globalThis
    i18n.install(target)
    const browser = (target as unknown as { browser: { runtime: { getManifest: () => { version: string, name: string }, getURL: (path: string) => string } } }).browser
    expect(browser.runtime.getManifest()).toEqual({
      manifest_version: 3,
      name: "OpenTranslate",
      version: "1.35.1",
    })
    expect(browser.runtime.getURL("/icon/128.png")).toContain("icon/128.png")
  })
})
