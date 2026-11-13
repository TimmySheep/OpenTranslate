# OpenTranslate regression verification

From the repository root, run:

```bash
./tools/verify/verify.sh
```

The script runs every check even if an earlier one fails, prints an `OK` or `FAIL`
for each, shows a final summary, and exits non-zero if any check fails:

1. `pnpm build:safari` from `extension/`.
2. `npx vitest run` from `extension/` (all unit tests). Project dependencies must
   already be installed; the script checks for the local Vitest binary so `npx`
   will not download a package unexpectedly.
3. `xcodebuild` for the `OpenTranslate (iOS)` scheme using a generic iOS Simulator
   destination, with code signing disabled.
4. `xcodebuild` for the `OpenTranslate (macOS)` scheme using a generic macOS
   destination, with `MACOSX_DEPLOYMENT_TARGET=12.0` and
   `CODE_SIGNING_ALLOWED=NO`.
5. A git diff check against `HEAD`, including non-ignored untracked files. It
   reports failure if protected paths changed: Xcode project files (`*.pbxproj`),
   entitlements (`*.entitlements`), `SharedSettingsStore.swift`, or the extension's
   translation core (host translation utilities, translation background flow,
   translation controls/input flow, prompts, and translation state/types).

The build commands may create their normal generated build products. The script
does not install dependencies, regenerate the Xcode project, or modify source files.
