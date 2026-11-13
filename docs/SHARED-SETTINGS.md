# Same-device shared settings (App ↔ Safari extension)

## Goal

One configuration per device install, editable from both the companion app and the Safari Web Extension options UI.

## Architecture

```
┌─────────────────────┐     App Group UserDefaults      ┌──────────────────────────┐
│ Companion App       │◄────────────────────────────────►│ SafariWebExtensionHandler│
│ (WKWebView Main)    │   group.net.timhuang.opentranslate│ (nativeMessaging)        │
└─────────────────────┘                                  └────────────▲─────────────┘
                                                                      │ sendNativeMessage
                                                           ┌──────────┴──────────┐
                                                           │ Extension JS        │
                                                           │ local:config cache  │
                                                           └─────────────────────┘
```

- **Source of truth (same device):** App Group JSON + meta (`schemaVersion`, `lastModifiedAt`, `source`).
- **Extension runtime cache:** existing WXT `local:config` (`browser.storage.local`).
- **Conflict policy:** higher `lastModifiedAt` wins. Stale App Group writes return `stale_write`.
- **Migration:** if App Group empty and extension has config → push once and set migration flag. Empty local never overwrites non-empty shared with defaults.
- **Safari profiles:** App Group is device-global (not per `SFExtensionProfileKey`). Documented product choice for “configure once”.

## Native message protocol

| type | purpose |
|------|---------|
| `sharedSettings.status` | availability / meta |
| `sharedSettings.get` | full config JSON |
| `sharedSettings.set` | write config + meta |
| `sharedSettings.markMigrated` | set migration flag |
| `ping` | health |

Never log full payloads (may contain API keys until Keychain split).

## Pending Apple Developer approval (do not change portal without OK)

1. App Group **`group.net.timhuang.opentranslate`** registered under team **`JY5U4D6JD3`**.
2. Enable that App Group on App IDs `net.timhuang.opentranslate` and `net.timhuang.opentranslate.extension` (iOS + macOS; use lowercase `.extension` to match App Store / TestFlight).
3. Regenerate provisioning profiles that include that App Group.
4. (Later) iCloud / Keychain Sharing entitlements for cross-device and secret sync — not enabled in this phase.

Entitlement files are already in the Xcode project; device builds will fail or silently lack the suite until the group is registered.

## App editing scope (this phase)

Companion app can view shared status and edit **default target language** into the App Group. Full provider/API UI remains in the extension options page; both sides share the same App Group blob after sync.

## iCloud / Keychain

Deferred. Ordinary settings sync and API Key Keychain sync are separate follow-ups.
