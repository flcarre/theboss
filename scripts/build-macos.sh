#!/bin/sh
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/installers}"
mkdir -p "$OUT"
(cd app && npx tauri build --target universal-apple-darwin --bundles app,dmg)
node scripts/collect-installers.mjs macOS "$OUT"
