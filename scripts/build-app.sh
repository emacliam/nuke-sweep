#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --scratch-path .build
APP="${NUKE_APP_PATH:-$PWD/dist/Nuke Sweep.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Nuke "$APP/Contents/MacOS/Nuke"
# Localization: .lproj directories go into the app bundle's Resources, where
# Bundle.main finds them. SwiftUI's Text/Button/Label take a LocalizedStringKey,
# so every literal in a view localizes from here with no call-site change.
# Keys missing from a translation fall back to the English source text.
for LPROJ in Resources/*.lproj(N); do
  [[ -d "$LPROJ" ]] || continue
  mkdir -p "$APP/Contents/Resources/${LPROJ:t}"
  for resource in "$LPROJ"/*.strings(N) "$LPROJ"/*.stringsdict(N); do
    cp "$resource" "$APP/Contents/Resources/${LPROJ:t}/"
  done
done

swift scripts/make-icon.swift "$PWD/.build"
python3 scripts/package-icon.py .build/NukeSweep.iconset "$APP/Contents/Resources/Nuke.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Nuke</string>
<key>CFBundleIdentifier</key><string>com.zyncraft.nukesweep</string>
<key>CFBundleIconFile</key><string>Nuke</string>
<key>CFBundleName</key><string>Nuke Sweep</string>
<key>CFBundleDisplayName</key><string>Nuke Sweep</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSDocumentsFolderUsageDescription</key><string>Nuke Sweep measures folders you choose and moves only reviewed items to Trash.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Nuke Sweep measures downloaded files so you can review what to keep or move to Trash.</string>
<key>NSDesktopFolderUsageDescription</key><string>Nuke Sweep measures Desktop items you choose and requires review before cleanup.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Nuke Sweep inspects folders you choose on external drives and cleans only reviewed items.</string>
<key>NSNetworkVolumesUsageDescription</key><string>Nuke Sweep inspects folders you choose on network volumes; cleanup requires review and write access.</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSExceptionDomains</key><dict><key>localhost</key><dict><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict><key>127.0.0.1</key><dict><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict></dict></dict>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Nuke Sweep widget navigation</string><key>CFBundleURLSchemes</key><array><string>nuke</string></array></dict></array>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NUKE_VERSION:-0.9.0}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NUKE_BUILD_NUMBER:-11}" "$APP/Contents/Info.plist"
NUKE_APP_PATH="$APP" ./scripts/build-widgets.sh
SIGN="${NUKE_SIGN_IDENTITY:--}"
if [[ "$SIGN" == "-" ]]; then
  codesign --force --sign - "$APP"
elif [[ "$SIGN" == Developer\ ID\ Application:* ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN" "$APP"
else
  codesign --force --options runtime --sign "$SIGN" "$APP"
fi
echo "Built $APP"
