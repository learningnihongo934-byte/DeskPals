#!/bin/bash
# Builds DeskPals.app into build/.
#   ./build.sh           build the app
#   ./build.sh run       build and launch it
#   ./build.sh preview   render every pet and pose to build/preview.png
#   ./build.sh install   build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DeskPals"
APP="build/DeskPals.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskPals"
"$BIN" --iconset build/AppIcon.iconset
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DeskPals</string>
    <key>CFBundleDisplayName</key><string>DeskPals</string>
    <key>CFBundleIdentifier</key><string>tech.rennko.deskpals</string>
    <key>CFBundleExecutable</key><string>DeskPals</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

# Your own pets (git-ignored), installed where the app looks for custom pets.
if compgen -G "private-pets/*.json" >/dev/null; then
    mkdir -p "$HOME/Library/Application Support/DeskPals/Pets"
    cp private-pets/*.json "$HOME/Library/Application Support/DeskPals/Pets/"
fi

case "${1:-}" in
    run) pkill -x DeskPals 2>/dev/null || true; open "$APP" ;;
    preview) "$APP/Contents/MacOS/DeskPals" --preview build/preview.png && echo "Wrote build/preview.png" ;;
    install) rm -rf /Applications/DeskPals.app && cp -R "$APP" /Applications/ && echo "Installed to /Applications" ;;
esac
