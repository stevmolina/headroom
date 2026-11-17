#!/usr/bin/env bash
# Builds Headroom.app (release) and installs it to /Applications.
# Signs with your Apple Development identity when one is in the keychain;
# menu bar managers on macOS 27 (holzBar, Thaw) hide an ad-hoc app in
# ~/Applications even when it is set to stay visible.
# Usage: scripts/bundle.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Headroom"
APP="build/Headroom.app"
VERSION="0.1.$(git rev-list --count HEAD 2>/dev/null || echo 0)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Headroom"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Headroom</string>
  <key>CFBundleDisplayName</key><string>Headroom</string>
  <key>CFBundleIdentifier</key><string>dev.stevmolina.headroom</string>
  <key>CFBundleExecutable</key><string>Headroom</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
IDENTITY="${HEADROOM_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP" >/dev/null
else
  codesign --force --sign - "$APP" >/dev/null
fi

if [[ "${1:-}" != "--no-install" ]]; then
  pkill -x Headroom 2>/dev/null || true
  rm -rf "/Applications/Headroom.app" "$HOME/Applications/Headroom.app"
  cp -R "$APP" "/Applications/Headroom.app"
  open "/Applications/Headroom.app"
  echo "Installed and opened /Applications/Headroom.app"
fi
