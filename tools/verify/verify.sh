#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIR="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)"
XCODE_PROJECT="$REPO_ROOT/apple/OpenTranslate/OpenTranslate.xcodeproj"

STEP_NAMES=()
STEP_RESULTS=()
FAILURES=0

run_step() {
  local name="$1"
  shift

  printf '\n==> %s\n' "$name"
  if "$@"; then
    printf 'OK   %s\n' "$name"
    STEP_RESULTS+=(OK)
  else
    local status=$?
    printf 'FAIL %s (exit %s)\n' "$name" "$status"
    STEP_RESULTS+=(FAIL)
    FAILURES=$((FAILURES + 1))
  fi
  STEP_NAMES+=("$name")
}

run_in_extension() {
  (
    cd "$REPO_ROOT/extension" && "$@"
  )
}

run_vitest() {
  if [[ ! -x "$REPO_ROOT/extension/node_modules/.bin/vitest" ]]; then
    printf 'Vitest is not installed in extension/node_modules; install project dependencies first.\n' >&2
    return 127
  fi

  run_in_extension npx vitest run
}

build_ios() {
  xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme 'OpenTranslate (iOS)' \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
}

build_macos() {
  xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme 'OpenTranslate (macOS)' \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    MACOSX_DEPLOYMENT_TARGET=12.0 \
    CODE_SIGNING_ALLOWED=NO \
    build
}

is_protected_path() {
  case "$1" in
    *.pbxproj | *.entitlements | */SharedSettingsStore.swift | SharedSettingsStore.swift | \
      extension/src/utils/host/translate/* | \
      extension/src/entrypoints/background/translation-* | \
      extension/src/entrypoints/background/page-translation-state.ts | \
      extension/src/entrypoints/background/llm-generate-text.ts | \
      extension/src/entrypoints/host.content/translation-control/* | \
      extension/src/entrypoints/selection.content/input-translation/* | \
      extension/src/utils/prompts/translate.ts | \
      extension/src/utils/atoms/translation-state.ts | \
      extension/src/types/translation-state.ts | \
      extension/src/types/background-generate-text.ts | \
      extension/src/types/config/translate.ts)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_protected_changes() {
  local changed_files
  local path
  local protected_paths=()

  if ! changed_files=$(
    {
      git -C "$REPO_ROOT" diff --no-renames --name-only HEAD -- || exit 1
      git -C "$REPO_ROOT" ls-files --others --exclude-standard || exit 1
    } | LC_ALL=C sort -u
  ); then
    printf 'Could not inspect git changes.\n' >&2
    return 2
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if is_protected_path "$path"; then
      protected_paths+=("$path")
    fi
  done <<< "$changed_files"

  if ((${#protected_paths[@]} > 0)); then
    printf 'Protected files changed:\n' >&2
    printf '  - %s\n' "${protected_paths[@]}" >&2
    return 1
  fi

  printf 'No protected files changed.\n'
}

run_step 'Safari extension build' run_in_extension pnpm build:safari
run_step 'Vitest unit tests' run_vitest
run_step 'iOS Xcode compile' build_ios
run_step 'macOS Xcode compile (deployment target 12.0)' build_macos
run_step 'Protected-file diff check' check_protected_changes

printf '\n== Summary ==\n'
for index in "${!STEP_NAMES[@]}"; do
  printf '  %-48s %s\n' "${STEP_NAMES[$index]}" "${STEP_RESULTS[$index]}"
done

if ((FAILURES > 0)); then
  printf '\nRegression verification FAILED (%s step(s) failed).\n' "$FAILURES"
  exit 1
fi

printf '\nRegression verification PASSED (all %s steps succeeded).\n' "${#STEP_NAMES[@]}"
