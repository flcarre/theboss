#!/bin/sh
set -e
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit your changes first: the Linux build packages the committed tree." >&2
  exit 1
fi
VERSION="v$(node -p "require('./app/package.json').version")"
OUT="build/installers/$VERSION"
rm -rf "$OUT"
./scripts/build-macos.sh "$OUT"
./scripts/build-windows.sh "$OUT"
./scripts/build-linux.sh "$OUT"
(cd "$OUT" && shasum -a 256 * > SHA256SUMS.txt)
if ! git rev-parse -q --verify "refs/tags/$VERSION" > /dev/null; then
  git tag "$VERSION"
fi
git push origin "$VERSION"
gh release delete "$VERSION" --repo flcarre/theboss-releases --yes --cleanup-tag 2> /dev/null || true
gh release create "$VERSION" "$OUT"/* \
  --repo flcarre/theboss-releases \
  --title "The Boss $VERSION" \
  --notes "Download The Boss for macOS (Apple Silicon and Intel), Windows or Linux. Install notes: https://theboss-iota.vercel.app/#download" \
  --latest
echo "Published https://github.com/flcarre/theboss-releases/releases/tag/$VERSION"
