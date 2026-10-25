#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$PWD/dist/Usage Monitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/UsageMonitor" "$APP/Contents/MacOS/UsageMonitor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Usage Monitor</string>
  <key>CFBundleDisplayName</key><string>Usage Monitor</string>
  <key>CFBundleIdentifier</key><string>io.github.chlee1252.usage-limit-monitor</string>
  <key>CFBundleExecutable</key><string>UsageMonitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '\nBuilt: %s\nRun: open "%s"\n' "$APP" "$APP"
