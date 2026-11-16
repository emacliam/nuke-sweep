#!/bin/zsh
set -eu
cd "${0:A:h:h}"

app="$1"
configuration="$2"
architecture="$(lipo -archs "$app/Contents/MacOS/Nuke")"
deployment_target=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
objects="$PWD/.build/out/Intermediates.noindex/Nuke.build/$configuration/Nuke-p.build/Objects-normal/$architecture"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

find "$objects" -maxdepth 1 -name '*.swiftconstvalues' > "$scratch/constants"
test -s "$scratch/constants"
xcrun appintentsmetadataprocessor \
  --module-name Nuke \
  --output "$scratch" \
  --toolchain-dir "$(dirname "$(dirname "$(xcrun -f swiftc)")")" \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
  --platform-family macOS \
  --deployment-target "$deployment_target" \
  --target-triple "$architecture-apple-macos$deployment_target" \
  --source-file-list "$objects/Nuke.SwiftFileList" \
  --swift-const-vals-list "$scratch/constants"

metadata="$scratch/Metadata.appintents"
python3 - "$metadata/extract.actionsdata" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    metadata = json.load(file)

expected = {"CheckThisMacIntent", "ClearableSpaceIntent"}
missing = expected - metadata["actions"].keys()
if missing:
    sys.exit("Missing App Intents metadata for " + ", ".join(sorted(missing)))
if len(metadata["autoShortcuts"]) < len(expected):
    sys.exit("Missing App Shortcuts metadata")
PY
ditto "$metadata" "$app/Contents/Resources/Metadata.appintents"
