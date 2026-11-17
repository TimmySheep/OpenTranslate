import type { UserConfig } from "vite"
import type { UserConfig as WxtUserConfig } from "wxt"
import { readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import { defineConfig } from "wxt"
import base from "./wxt.config"

const parent = base as WxtUserConfig

export default defineConfig({
  ...parent,
  filterEntrypoints: ["translate-app"],
  outDirTemplate: "translate-app-final",
  vite: (env) => {
    const resolved = typeof parent.vite === "function" ? parent.vite(env) : parent.vite
    return {
      ...resolved,
      base: "./",
      plugins: (resolved as UserConfig | undefined)?.plugins ?? [],
    }
  },
  hooks: {
    ...parent.hooks,
    "build:done": async (wxt) => {
      const htmlPath = path.join(wxt.config.outDir, "translate-app.html")
      const html = await readFile(htmlPath, "utf8")
      let fixed = html.replaceAll("../../../", "./").replaceAll(" crossorigin", "")
      const polyfill = `<script id="translate-app-runtime-polyfill">
(function () {
  function getURL(path) {
    var href = (globalThis.location && location.href) ? location.href : "https://opentranslate.app/translate-app.html";
    var directory = href.slice(0, href.lastIndexOf("/") + 1);
    var relative = String(path || "");
    if (relative.charAt(0) === "/") relative = relative.slice(1);
    return new URL(relative, directory).href;
  }
  var runtime = (globalThis.browser && globalThis.browser.runtime) || {};
  runtime.id = runtime.id || "opentranslate-app";
  runtime.getManifest = runtime.getManifest || function () {
    return { manifest_version: 3, name: "OpenTranslate", version: "1.35.1" };
  };
  runtime.getURL = runtime.getURL || getURL;
  var i18n = (globalThis.browser && globalThis.browser.i18n) || {};
  i18n.getMessage = i18n.getMessage || function () { return ""; };
  i18n.getUILanguage = i18n.getUILanguage || function () { return navigator.language || "en"; };
  var api = globalThis.browser || {};
  api.runtime = runtime;
  api.i18n = i18n;
  globalThis.browser = api;
  globalThis.chrome = api;
})();
</script>
`
      if (!fixed.includes("translate-app-runtime-polyfill")) {
        if (fixed.includes("<head>"))
          fixed = fixed.replace("<head>", `<head>${polyfill}`)
        else
          fixed = `${polyfill}${fixed}`
      }
      if (fixed !== html)
        await writeFile(htmlPath, fixed)
    },
  },
})
