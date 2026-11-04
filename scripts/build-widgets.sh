#!/bin/zsh
set -eu
cd "${0:A:h:h}"
APP="$PWD/dist/Nuke Sweep.app"
EXTENSION="$APP/Contents/PlugIns/NukeWidgets.appex"
RELEASE="$PWD/.build/release"
mkdir -p "$EXTENSION/Contents/MacOS"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
# Swift's Xcode build engine emits combined module objects alongside the binary.
# Older SwiftPM layouts keep per-source objects and a Modules directory.
if [[ -f "$RELEASE/NukeMetrics.o" && -f "$RELEASE/NukeWidgetUI.o" ]]; then
  MODULES="$RELEASE"
  OBJECTS=("$RELEASE/NukeMetrics.o" "$RELEASE/NukeWidgetUI.o")
else
  MODULES="$RELEASE/Modules"
  OBJECTS=("$RELEASE/NukeMetrics.build/"*.o "$RELEASE/NukeWidgetUI.build/"*.o)
fi
xcrun swiftc -O -swift-version 5 -parse-as-library -application-extension \
  -sdk "$SDK_PATH" -target "$ARCH-apple-macosx14.0" \
  -module-name NukeWidgets -I "$MODULES" \
  Widgets/NukeWidgets.swift \
  "${OBJECTS[@]}" \
  -framework SwiftUI -framework WidgetKit \
  -o "$EXTENSION/Contents/MacOS/NukeWidgets"
cat > "$EXTENSION/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NukeWidgets</string>
<key>CFBundleIdentifier</key><string>local.nuke.mac.widgets</string>
<key>CFBundleName</key><string>Nuke Sweep Widgets</string>
<key>CFBundleDisplayName</key><string>Nuke Sweep</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>0.8.1</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
SIGN="${NUKE_SIGN_IDENTITY:--}"
if [[ "$SIGN" == "-" ]]; then
  codesign --force --sign - --entitlements Widgets/NukeWidgets.entitlements "$EXTENSION"
elif [[ "$SIGN" == Developer\ ID\ Application:* ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN" --entitlements Widgets/NukeWidgets.entitlements "$EXTENSION"
else
  codesign --force --options runtime --sign "$SIGN" --entitlements Widgets/NukeWidgets.entitlements "$EXTENSION"
fi
echo "Embedded WidgetKit extension: $EXTENSION"
