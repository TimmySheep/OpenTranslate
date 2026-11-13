declare module "virtual:app-locales" {
  import type { LocaleCatalog } from "./static-i18n"

  export const defaultLocale: string
  export const catalog: LocaleCatalog
}
