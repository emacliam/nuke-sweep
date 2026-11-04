#!/bin/zsh
set -eu
cd "${0:A:h:h}"

APP="$PWD/dist/Nuke Sweep.app"
[[ -d "$APP" ]] || { echo "No app bundle at $APP. Run ./scripts/build-app.sh first." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$PWD/dist/Nuke-Sweep-${VERSION}.dmg"
IDENTITY="${NUKE_SIGN_IDENTITY:-}"
PROFILE="${NUKE_NOTARY_PROFILE:-}"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nuke-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

codesign --verify --deep --strict "$APP"

if [[ -n "$PROFILE" ]]; then
  if [[ "$IDENTITY" != Developer\ ID\ Application:* ]]; then
    echo "Notarization requires a Developer ID Application identity, not '${IDENTITY:-ad-hoc}'." >&2
    exit 1
  fi
  ZIP=$(mktemp -d "${TMPDIR:-/tmp}/nuke-notary.XXXXXX")/Nuke-Sweep.zip
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv "$APP"
  rm -f "$ZIP"
fi

# ditto preserves bundle metadata, extended attributes and the code signature.
ditto "$APP" "$STAGE/Nuke Sweep.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "Nuke Sweep ${VERSION}" "$STAGE" "$DMG"
hdiutil verify "$DMG" >/dev/null

codesign --verify --deep --strict "$APP"
if [[ -n "$IDENTITY" ]]; then
  if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  else
    codesign --force --sign "$IDENTITY" "$DMG"
  fi
  codesign --verify "$DMG"
  echo "Signed $DMG with $IDENTITY"
fi
if [[ -n "$PROFILE" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
fi
echo "Built $DMG"
echo "SHA-256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
