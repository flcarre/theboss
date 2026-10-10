#!/bin/sh
set -e
cd "$(dirname "$0")/.."
VERSION="v$(node -p "require('./app/package.json').version")"
if ! git rev-parse -q --verify "refs/tags/$VERSION" > /dev/null; then
  git tag "$VERSION"
fi
git push origin "$VERSION"
gh workflow run release.yml --repo flcarre/theboss-releases -f ref="$VERSION"
echo "Building $VERSION: https://github.com/flcarre/theboss-releases/actions"
