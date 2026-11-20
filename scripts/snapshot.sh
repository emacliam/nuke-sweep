#!/bin/zsh
# Renders pages of the development build to PNGs, light and dark, using the
# app's own --snapshot mode (no screen-recording permission needed).
#   scripts/snapshot.sh [OUT_DIR] [page ...]     pages are Page raw values, e.g. "Find space" "Trash"
set -eu
cd "${0:A:h:h}"
OUT="${1:-snapshots/dev}"; shift || true
APP="dist/Nuke Sweep Development.app/Contents/MacOS/Nuke"
[[ -x "$APP" ]] || ./scripts/build-development.sh >/dev/null
pages=("$@"); (( ${#pages} )) || pages=("Find space" "Developer" "Trash" "Storage" "Apps" "History")
mkdir -p "$OUT"
for page in "${pages[@]}"; do
  for look in light dark; do
    pkill -f "Nuke Sweep Development.app/Contents/MacOS/Nuke" 2>/dev/null || true; sleep 1
    perl -e 'alarm 40; exec @ARGV' "$APP" --compact --without-status-item --demo-fixtures --capture-fresh \
      --snapshot "$OUT" --snapshot-page "$page" --appearance "$look" --snapshot-delay "${DELAY:-6}" --quit-after-snapshot >/dev/null 2>&1 || true
  done
done
ls "$OUT"
