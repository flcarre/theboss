#!/bin/sh
set -e
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
swift build -c release
[ -f build/AppIcon.icns ] || python3 scripts/make_icon.py
APP=build/TheBoss.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TheBoss "$APP/Contents/MacOS/TheBoss"
cp -R Sources/TheBoss/Assets "$APP/Contents/Resources/Assets"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>The Boss</string>
  <key>CFBundleDisplayName</key><string>The Boss</string>
  <key>CFBundleIdentifier</key><string>io.theboss.app</string>
  <key>CFBundleExecutable</key><string>TheBoss</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
