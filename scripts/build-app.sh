#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --scratch-path .build
APP="$PWD/dist/Nuke Sweep.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Nuke "$APP/Contents/MacOS/Nuke"
swift scripts/make-icon.swift "$PWD/.build"
python3 scripts/package-icon.py .build/NukeSweep.iconset "$APP/Contents/Resources/Nuke.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Nuke</string>
<key>CFBundleIdentifier</key><string>local.nuke.mac</string>
<key>CFBundleIconFile</key><string>Nuke</string>
<key>CFBundleName</key><string>Nuke Sweep</string>
<key>CFBundleDisplayName</key><string>Nuke Sweep</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.2</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSDocumentsFolderUsageDescription</key><string>Nuke Sweep measures folders you choose and moves only reviewed items to Trash.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Nuke Sweep measures downloaded files so you can review what to keep or move to Trash.</string>
<key>NSDesktopFolderUsageDescription</key><string>Nuke Sweep measures Desktop items you choose and requires review before cleanup.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Nuke Sweep inspects folders you choose on external drives and cleans only reviewed items.</string>
<key>NSNetworkVolumesUsageDescription</key><string>Nuke Sweep inspects folders you choose on network volumes; cleanup requires review and write access.</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Nuke Sweep widget navigation</string><key>CFBundleURLSchemes</key><array><string>nuke</string></array></dict></array>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
./scripts/build-widgets.sh
SIGN="${NUKE_SIGN_IDENTITY:--}"
if [[ "$SIGN" == "-" ]]; then
  codesign --force --sign - "$APP"
elif [[ "$SIGN" == Developer\ ID\ Application:* ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN" "$APP"
else
  codesign --force --options runtime --sign "$SIGN" "$APP"
fi
echo "Built $APP"
