#!/bin/bash
# Builds the release binary and assembles "TV Menubar Remote.app" in dist/.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TV Menubar Remote"
BUNDLE_ID="com.nuwan.mac-tv-menubar-remote"
DIST="dist/$APP_NAME.app"

swift build -c release

rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"

cp ".build/release/MacTVRemote" "$DIST/Contents/MacOS/MacTVRemote"

if [ ! -f "AppIcon.icns" ]; then
    ./scripts/generate_icon.sh
fi
cp "AppIcon.icns" "$DIST/Contents/Resources/AppIcon.icns"

cat > "$DIST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MacTVRemote</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.3</string>
    <key>CFBundleVersion</key><string>9</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Finds and controls your Panasonic VIERA TV on the local network.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$DIST"

echo "Built: $DIST"
echo "Run:   open \"$DIST\""
echo "Install: cp -R \"$DIST\" /Applications/"
