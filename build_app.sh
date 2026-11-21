#!/bin/bash
# Builds FormationFlightX.app (release).
#   ./build_app.sh                  for this Mac, next to this script
#   ./build_app.sh x86_64 dist/x86  for another architecture (arm64 or x86_64), into a folder
set -euo pipefail
cd "$(dirname "$0")"
VERSION="1.0.1"     # shown in Finder and used in the release file names
BUILD="2"
ARCH="${1:-}"
OUT="${2:-.}"
if [ -n "$ARCH" ]; then
    swift build -c release --arch "$ARCH"
    BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/FormationFlightX"
else
    swift build -c release
    BIN=".build/release/FormationFlightX"
fi
mkdir -p "$OUT"
APP="$OUT/FormationFlightX.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon.png Resources/Splash.jpg Resources/RockFPV.png "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R Resources/Previews "$APP/Contents/Resources/Previews"
cp "$BIN" "$APP/Contents/MacOS/FormationFlightX"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FormationFlightX</string>
    <key>CFBundleDisplayName</key><string>FormationFlightX</string>
    <key>CFBundleIdentifier</key><string>app.formationflightx.sim</string>
    <key>CFBundleExecutable</key><string>FormationFlightX</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.simulation-games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>GCSupportsControllerUserInteraction</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>FormationFlightX finds the other pilots on your local network so that you can fly in formation together.</string>
    <key>NSMicrophoneUsageDescription</key><string>FormationFlightX uses the microphone so that you can talk to the other pilots while you fly together.</string>
    <key>NSBonjourServices</key><array><string>_formflightx._udp</string></array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
