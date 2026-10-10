#!/bin/sh
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/installers}"
mkdir -p "$OUT"
git archive --format=tar HEAD | docker run --rm -i --platform linux/amd64 \
  -v "$PWD/$OUT:/out" -v theboss-linux-cargo:/root/.cargo -v theboss-linux-rustup:/root/.rustup -v theboss-linux-target:/src/target \
  ubuntu:22.04 bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl build-essential file libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev patchelf libfuse2 > /dev/null
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null
    apt-get install -y -qq nodejs > /dev/null
    [ -x /root/.cargo/bin/rustup ] || curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal > /dev/null
    . /root/.cargo/env
    rustup default stable > /dev/null
    mkdir -p /src && cd /src && tar -x
    cargo test -p boss-core
    cd app && npm ci --silent
    npx tauri build --bundles deb
    export APPIMAGE_EXTRACT_AND_RUN=1
    npx tauri build --bundles appimage > /dev/null 2>&1 || true
    for tool in /root/.cache/tauri/*.AppImage; do
      printf "\000\000\000" | dd of="$tool" bs=1 seek=8 count=3 conv=notrunc 2> /dev/null
    done
    npx tauri build --bundles appimage
    cd /src && node scripts/collect-installers.mjs Linux /out
  '
