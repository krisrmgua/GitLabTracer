#!/bin/bash
# Assembles GitLab Tracer.app from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")"

APP="GitLab Tracer.app"
BUNDLE_ID="com.kris.gitlabtracer"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/GitLabTracer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GitLabTracer"
cp Artwork/GitLabTracer.icns "$APP/Contents/Resources/GitLabTracer.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GitLab Tracer</string>
  <key>CFBundleDisplayName</key><string>GitLab Tracer</string>
  <key>CFBundleExecutable</key><string>GitLabTracer</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconName</key><string>GitLabTracer</string>
  <key>CFBundleIconFile</key><string>GitLabTracer.icns</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Kristopher Simmons</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $PWD/$APP"
