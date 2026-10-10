#!/bin/sh
set -e
cd "$(dirname "$0")/.."
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$DEV/Frameworks/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
  swift test -Xswiftc -F$DEV/Frameworks -Xlinker -F$DEV/Frameworks -Xlinker -rpath -Xlinker $DEV/Frameworks -Xlinker -rpath -Xlinker $DEV/usr/lib "$@"
else
  swift test "$@"
fi
