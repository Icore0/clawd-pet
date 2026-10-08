#!/bin/sh
# Builds a universal Wigglet.app next to this script.   Usage: ./build.sh
set -e
PRODUCT_NAME="Wigglet"
BINARY_NAME=Wigglet
BUNDLE_ID=dev.wigglet.app
PRODUCT_SLUG=wigglet
cd "$(dirname "$0")"
A=$BINARY_NAME.app
rm -rf $A build && mkdir -p $A/Contents/MacOS build
cat > Sources/Product.swift <<EOF
let PRODUCT_NAME = "$PRODUCT_NAME"
let PRODUCT_SLUG = "$PRODUCT_SLUG"
let BUNDLE_ID = "$BUNDLE_ID"
EOF
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $ARCH-apple-macos13.0 Sources/*.swift -o build/$BINARY_NAME-$ARCH
done
lipo -create build/$BINARY_NAME-arm64 build/$BINARY_NAME-x86_64 -output $A/Contents/MacOS/$BINARY_NAME
strip -S $A/Contents/MacOS/$BINARY_NAME
mkdir -p $A/Contents/Resources && cp Resources/AppIcon.icns $A/Contents/Resources/ 2>/dev/null || true
cat > $A/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$BINARY_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>$PRODUCT_NAME</string>
<key>CFBundleDisplayName</key><string>$PRODUCT_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1.0.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><false/>
<key>NSAppleEventsUsageDescription</key><string>Jump to session selects the Terminal or iTerm2 tab where that Claude Code session runs.</string>
<key>NSMicrophoneUsageDescription</key><string>$PRODUCT_NAME's mic button starts macOS Dictation so you can talk instead of type.</string>
</dict></plist>
P
if [ -n "$CODESIGN_ID" ]; then
  codesign --force --options runtime -s "$CODESIGN_ID" $A
else
  codesign --force -s - $A
fi
rm -rf build
echo "built $PWD/$A"
