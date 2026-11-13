import "./i18n"
import "@/utils/zod-config"
import type { Config } from "@/types/config/config"
import type { ThemeMode } from "@/types/config/theme"
import { QueryClientProvider } from "@tanstack/react-query"
import { Provider as JotaiProvider } from "jotai"
import { useHydrateAtoms } from "jotai/utils"
import * as React from "react"
import { HashRouter } from "react-router"
import AppToast from "@/components/app-toast"
import { HelpButton } from "@/components/help-button"
import { ThemeProvider } from "@/components/providers/theme-provider"
import { RecoveryBoundary } from "@/components/recovery/recovery-boundary"
import { SidebarProvider } from "@/components/ui/base-ui/sidebar"
import { TooltipProvider } from "@/components/ui/base-ui/tooltip"
import { configAtom } from "@/utils/atoms/config"
import { baseThemeModeAtom } from "@/utils/atoms/theme"
import { DEFAULT_CONFIG } from "@/utils/constants/config"
import { renderPersistentReactRoot } from "@/utils/react-root"
import { queryClient } from "@/utils/tanstack-query"
import { applyTheme, isDarkMode } from "@/utils/theme"
import App from "../options/app"
import { AppSidebar } from "../options/app-sidebar"
import { SettingsSearch } from "../options/command-palette/settings-search"
import { installAppStorageAdapter, loadAppSettings } from "./bootstrap"
import "@/assets/styles/theme.css"
import "../options/style.css"

installAppStorageAdapter()

function HydrateAtoms({
  initialValues,
  children,
}: {
  initialValues: [
    [typeof configAtom, Config],
    [typeof baseThemeModeAtom, ThemeMode],
  ]
  children: React.ReactNode
}) {
  useHydrateAtoms(initialValues)
  return children
}

async function initApp() {
  const root = document.getElementById("root")!
  root.className = "antialiased bg-background"

  const { config, themeMode } = await loadAppSettings()
  const initialConfig = config ?? DEFAULT_CONFIG

  applyTheme(document.documentElement, isDarkMode(themeMode) ? "dark" : "light")

  renderPersistentReactRoot(root, (
    <React.StrictMode>
      <JotaiProvider>
        <HydrateAtoms initialValues={[[configAtom, initialConfig], [baseThemeModeAtom, themeMode]]}>
          <QueryClientProvider client={queryClient}>
            <HashRouter>
              <SidebarProvider>
                <ThemeProvider>
                  <TooltipProvider>
                    <AppToast />
                    <RecoveryBoundary>
                      <AppSidebar />
                      <App />
                      <HelpButton />
                      <SettingsSearch />
                    </RecoveryBoundary>
                  </TooltipProvider>
                </ThemeProvider>
              </SidebarProvider>
            </HashRouter>
          </QueryClientProvider>
        </HydrateAtoms>
      </JotaiProvider>
    </React.StrictMode>
  ))
}

void initApp()
