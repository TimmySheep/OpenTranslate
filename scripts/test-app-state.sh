#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/app-state-selftest"
STORE_SOURCE="$REPO_ROOT/apple/OpenTranslate/Shared (App)/TranslationHistoryStore.swift"
PIN_STORE_SOURCE="$REPO_ROOT/apple/OpenTranslate/Shared (App)/LanguagePinStore.swift"
GENERATION_SETTINGS_SOURCE="$REPO_ROOT/apple/OpenTranslate/Shared (App)/NativeGenerationSettings.swift"
TEMP_ROOT="${TMPDIR:-/private/var/folders/p1/3pqxj392m381v0g293m9rgc0000gn/T/opencode}"
TEST_DIR="$(mktemp -d "${TEMP_ROOT%/}/opentranslate-app-state.XXXXXX")"
TEST_BINARY="$TEST_DIR/app-state-selftest"

swiftc -parse-as-library "$STORE_SOURCE" "$PIN_STORE_SOURCE" "$GENERATION_SETTINGS_SOURCE" "$SCRIPT_DIR/main.swift" -o "$TEST_BINARY"
APP_STATE_TEST_DIR="$TEST_DIR" "$TEST_BINARY"
