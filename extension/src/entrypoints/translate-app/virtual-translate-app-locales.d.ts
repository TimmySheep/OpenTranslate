declare module "virtual:translate-app-locales" {
  import type { LocaleCatalog } from "../options-app/static-i18n"

  export const defaultLocale: string
  export const catalog: LocaleCatalog
}
