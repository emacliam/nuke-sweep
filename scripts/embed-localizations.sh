#!/bin/zsh
set -eu
cd "${0:A:h:h}"

resources="$1/Contents/Resources"
for localization in Resources/*.lproj(N/); do
  destination="$resources/${localization:t}"
  mkdir -p "$destination"
  for catalog in "$localization"/*.strings(N) "$localization"/*.stringsdict(N); do
    plutil -lint -s "$catalog"
    cp "$catalog" "$destination/"
  done
done
