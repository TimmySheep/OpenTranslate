import type { UserConfig } from "wxt"
import { readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { defineConfig } from "wxt"
import base from "./wxt.config"

const parent = base as UserConfig

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
