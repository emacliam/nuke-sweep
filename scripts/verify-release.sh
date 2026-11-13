#!/bin/zsh
set -eu
cd "${0:A:h:h}"

strict=0
if [[ "${1:-}" == "--strict" ]]; then strict=1; shift; fi
DMG="${1:-dist/Nuke-Sweep-0.9.0.dmg}"
CHECKSUM="${2:-${DMG:r}.sha256}"
problems=0

[[ -f "$DMG" ]] || { echo "Missing $DMG" >&2; exit 1; }
scratch=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nuke-release.XXXXXX")
mount="$scratch/mount"
mkdir "$mount"
mounted=0
cleanup() {
  if (( mounted )); then
    /usr/bin/hdiutil detach "$mount" >/dev/null || return
  fi
  rm -f "$scratch/check.log"
  rmdir "$mount" "$scratch"
}
trap cleanup EXIT

check() {
  local label="$1"
  shift
  if "$@" >"$scratch/check.log" 2>&1; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    tail -3 "$scratch/check.log"
    problems=$((problems+1))
  fi
}

developer_id_team() {
  local details
  details=$(codesign -dv --verbose=4 "$1" 2>&1) || return 1
  [[ "$details" == *$'\n'Authority=Developer\ ID\ Application:* ]] || return 1
  local team
  team=$(print -r -- "$details" | sed -n 's/^TeamIdentifier=//p')
  [[ -n "$team" && "$team" != "not set" ]] || return 1
  print -r -- "$team"
}

check "DMG integrity" hdiutil verify "$DMG"
check "DMG signature" codesign --verify --strict "$DMG"
check "DMG notarization ticket" xcrun stapler validate "$DMG"

actual=$(shasum -a 256 "$DMG" | awk '{print $1}')
if [[ -f "$CHECKSUM" ]]; then
  expected=$(awk 'NR == 1 {print tolower($1)}' "$CHECKSUM")
  if [[ "$expected" == "$actual" ]]; then
    echo "ok   SHA-256 matches $CHECKSUM"
  else
    echo "FAIL SHA-256 does not match $CHECKSUM"
    problems=$((problems+1))
  fi
elif (( strict )); then
  echo "FAIL missing checksum file $CHECKSUM"
  problems=$((problems+1))
fi
echo "sha256: $actual"

if ! hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" "$DMG"; then
  echo "FAIL could not mount the DMG" >&2
  exit 1
fi
mounted=1
APP="$mount/Nuke Sweep.app"
WIDGET="$APP/Contents/PlugIns/NukeWidgets.appex"
[[ -d "$APP" ]] || { echo "FAIL Nuke Sweep.app missing from DMG" >&2; exit 1; }

check "mounted app signature" codesign --verify --deep --strict "$APP"
check "mounted widget signature" codesign --verify --strict "$WIDGET"

check_bundle_id() {
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1")" == "$2" ]]
}
check "production app bundle ID" check_bundle_id "$APP/Contents/Info.plist" com.zyncraft.nukesweep
check "production widget bundle ID" check_bundle_id "$WIDGET/Contents/Info.plist" com.zyncraft.nukesweep.widgets
# A widget linked to start at `main` signs and notarizes cleanly, then traps the
# first time the system launches it. Only the entry symbol tells them apart.
if nm -u "$WIDGET/Contents/MacOS/NukeWidgets" 2>/dev/null | grep -q '_NSExtensionMain'; then
  echo "ok   widget enters at NSExtensionMain"
else
  echo "FAIL widget is not linked with -e _NSExtensionMain; it will crash when launched"
  problems=$((problems+1))
fi
check "mounted app Gatekeeper assessment" spctl -a -vv "$APP"
check "mounted app notarization ticket" xcrun stapler validate "$APP"
check "mounted app architecture" lipo -archs "$APP/Contents/MacOS/Nuke"

dmg_team=$(developer_id_team "$DMG") || dmg_team=""
app_team=$(developer_id_team "$APP") || app_team=""
widget_team=$(developer_id_team "$WIDGET") || widget_team=""
if [[ -n "$app_team" && "$dmg_team" == "$app_team" && "$widget_team" == "$app_team" ]]; then
  echo "ok   Developer ID team matches across DMG, app and widget ($app_team)"
else
  echo "FAIL Developer ID team is missing or inconsistent across DMG, app and widget"
  problems=$((problems+1))
fi

/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" | sed 's/^/version: /'
if (( problems )); then
  echo "Release verification found $problems problem(s)."
  if (( strict )); then exit 1; fi
else
  echo "Release verification passed."
fi
