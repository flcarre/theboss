#!/bin/sh
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/installers}"
mkdir -p "$OUT"
export PATH="$PWD/scripts/tools:/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:$HOME/.cargo/bin:$PATH"
(cd app && npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis)
node scripts/collect-installers.mjs Windows "$OUT"
