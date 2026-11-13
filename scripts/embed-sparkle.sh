#!/bin/zsh
set -eu
cd "${0:A:h:h}"

APP="$1"
CONFIGURATION="$2"
SOURCE="$PWD/.build/$CONFIGURATION/Sparkle.framework"
DESTINATION="$APP/Contents/Frameworks/Sparkle.framework"
SIGN="${NUKE_SIGN_IDENTITY:--}"

[[ -f "$SOURCE/Sparkle" ]] || { echo "Missing built Sparkle framework at $SOURCE" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
if [[ -d "$DESTINATION" ]]; then rm -rf "$DESTINATION"; fi
ditto "$SOURCE" "$DESTINATION"

sign_flags=()
if [[ "$SIGN" != "-" ]]; then sign_flags+=(--options runtime); fi
if [[ "$SIGN" == Developer\ ID\ Application:* ]]; then sign_flags+=(--timestamp); fi

VERSION="$DESTINATION/Versions/Current"
for component in "$VERSION"/XPCServices/*.xpc(N) "$VERSION"/Updater.app(N) "$VERSION"/Autoupdate(N); do
  codesign --force "${sign_flags[@]}" --sign "$SIGN" "$component"
done
codesign --force "${sign_flags[@]}" --sign "$SIGN" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
