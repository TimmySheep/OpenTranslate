import { Icon } from "@iconify/react"
import { browser, i18n } from "#imports"
import { isAppSettingsMode } from "@/utils/app-settings-mode"
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/base-ui/sidebar"

export function ToolsNav() {
  if (isAppSettingsMode())
    return null

  return (
    <SidebarGroup>
      <SidebarGroupLabel>{i18n.t("options.sidebar.tools")}</SidebarGroupLabel>
      <SidebarGroupContent>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton render={<a href={browser.runtime.getURL("/translation-hub.html")} target="_blank" rel="noopener noreferrer" />}>
              <Icon icon="tabler:language-hiragana" />
              <span>{i18n.t("options.tools.translationHub")}</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  )
}
