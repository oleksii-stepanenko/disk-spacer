#!/usr/bin/env bash
# make-app.sh — build DiskSpacerApp and assemble it into a real .app bundle.
#
# A bare SPM executable can't hold TCC permissions: Full Disk Access is granted
# to a bundle identity, so the app has to be a proper .app with a stable bundle
# id for the grant to stick across launches.
#
# Usage: ./Scripts/make-app.sh [--release] [--install]
#   --release   build with optimizations (default: debug)
#   --install   also copy the result into /Applications

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG=debug
INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
    --install) INSTALL=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="Disk Spacer"
BUNDLE_ID="com.oleksii.diskspacer"
APP="$ROOT/build/$APP_NAME.app"

echo "Building ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG" --product DiskSpacerApp
swift build -c "$CONFIG" --product diskspacer

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/DiskSpacerApp" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>          <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.utilities</string>
    <!-- Not sandboxed: the whole job is reading and clearing caches across
         the home directory, which the sandbox exists to prevent. -->
</dict>
</plist>
PLIST

# Ad-hoc signature. TCC keys the Full Disk Access grant to this identity, so a
# rebuild can invalidate it — if the app stops seeing protected paths, remove
# and re-add it in System Settings.
codesign --force --deep --sign - "$APP" 2>/dev/null \
  || echo "warning: codesign failed; the app will still run but FDA may not persist"

echo "Built: $APP"

if [[ $INSTALL -eq 1 ]]; then
  echo "Installing to /Applications …"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "Installed: /Applications/$APP_NAME.app"
fi

echo
echo "Run it with:   open '$APP'"
echo "CLI built at:  $BIN/diskspacer"
