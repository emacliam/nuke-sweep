#!/bin/zsh
set -eu
cd "${0:A:h:h}"
ARCHIVES="${1:?Pass a directory of notarized update archives}"
[[ -d "$ARCHIVES" ]] || { echo "Update archives directory does not exist" >&2; exit 1; }

TOOLS="$PWD/.build/artifacts/nuke/Sparkle/bin"
"$TOOLS/generate_appcast" --account com.zyncraft.nukesweep \
  --download-url-prefix https://sweep.zyncraft.com/downloads/ \
  --embed-release-notes "${ARCHIVES:A}"
