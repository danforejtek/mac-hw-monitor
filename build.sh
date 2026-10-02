#!/bin/zsh
# Builds HWMonitor with SwiftPM and assembles a menu-bar .app bundle (no Xcode needed).
# Usage: ./build.sh [--run] [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP=HWMonitor
OUT=build/$APP.app
VERSION=0.1.0

swift build -c release 2>&1 | grep -v "^\[" || true
BIN=$(swift build -c release --show-bin-path)/$APP
[[ -x "$BIN" ]] || { echo "build failed: $BIN not found"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>HW Monitor</string>
  <key>CFBundleIdentifier</key><string>com.hwmonitor.HWMonitor</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
echo -n "APPL????" > "$OUT/Contents/PkgInfo"
codesign --force --deep --sign - "$OUT" 2>/dev/null || echo "warning: ad-hoc codesign failed"
echo "built $OUT"

for arg in "$@"; do
  case $arg in
    --install) DEST=/Applications; [[ -w $DEST ]] || DEST="$HOME/Applications"; mkdir -p "$DEST"; pkill -x "$APP" 2>/dev/null || true; rm -rf "$DEST/$APP.app"; cp -R "$OUT" "$DEST/"; echo "installed to $DEST/$APP.app";;
    --run) pkill -x "$APP" 2>/dev/null || true; open "$OUT"; echo "launched";;
  esac
done
