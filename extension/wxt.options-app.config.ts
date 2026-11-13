import type { Plugin, UserConfig } from "vite"
import type { UserConfig as WxtUserConfig } from "wxt"
import { generateChromeMessages, parseMessagesFile } from "@wxt-dev/i18n/build"
import { readdir, readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "wxt"
import base from "./wxt.config"

const parent = base as WxtUserConfig
const extensionRoot = path.dirname(fileURLToPath(import.meta.url))
const localesDir = path.join(extensionRoot, "src/locales")
const VIRTUAL_APP_LOCALES = "virtual:app-locales"

function appLocalesPlugin(): Plugin {
  return {
    name: "app-locales",
    resolveId(id) {
      if (id === VIRTUAL_APP_LOCALES)
        return `\0${VIRTUAL_APP_LOCALES}`
    },
    async load(id) {
      if (id !== `\0${VIRTUAL_APP_LOCALES}`)
        return
      const catalog: Record<string, unknown> = {}
      for (const file of await readdir(localesDir)) {
        if (!file.endsWith(".yml") && !file.endsWith(".yaml"))
          continue
        const locale = file.replace(/\.ya?ml$/, "").replaceAll("-", "_")
        const parsed = await parseMessagesFile(path.join(localesDir, file))
        catalog[locale] = generateChromeMessages(parsed)
      }
      return `export const defaultLocale = "en"\nexport const catalog = ${JSON.stringify(catalog)}\n`
    },
  }
}

/**
 * Standalone build of the App settings UI.
 * Reuses the options page components, writes to `.output/options-app`,
 * and uses relative asset URLs so WKWebView can load the bundle from disk.
 */
export default defineConfig({
  ...parent,
  filterEntrypoints: ["options-app"],
  outDirTemplate: "options-app",
  vite: (env) => {
    const resolved = typeof parent.vite === "function" ? parent.vite(env) : parent.vite
    return {
      ...resolved,
      base: "./",
      plugins: [...((resolved as UserConfig | undefined)?.plugins ?? []), appLocalesPlugin()],
    }
  },
  hooks: {
    ...parent.hooks,
    "build:done": async (wxt) => {
      // Vite emits HTML as if it still lived at src/entrypoints/options-app/,
      // so asset hrefs become ../../../chunks/… — rewrite them to the actual
      // output layout (options-app.html next to chunks/ and assets/).
      const htmlPath = path.join(wxt.config.outDir, "options-app.html")
      const html = await readFile(htmlPath, "utf8")
      const fixed = html
        .replaceAll("../../../", "./")
        .replaceAll(" crossorigin", "")
      if (fixed !== html)
        await writeFile(htmlPath, fixed)
    },
  },
})
