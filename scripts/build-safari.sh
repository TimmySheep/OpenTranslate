#!/usr/bin/env bash
# Build the OpenTranslate web extension for Safari → extension/.output/safari-mv3
# and the App settings UI → extension/.output/options-app
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/extension"
WXT_SKIP_ENV_VALIDATION=true pnpm wxt build -b safari "$@"
echo "✓ Built → $REPO_ROOT/extension/.output/safari-mv3"
WXT_SKIP_ENV_VALIDATION=true pnpm wxt build -b safari -c wxt.options-app.config.ts
echo "✓ Built → $REPO_ROOT/extension/.output/options-app"
