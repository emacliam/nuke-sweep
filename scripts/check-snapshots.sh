#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./scripts/capture-snapshots.sh
exit_code=0
for baseline in snapshots/baseline/*.png; do
  [[ -f "$baseline" ]] || continue
  name="${baseline:t}"
  current="snapshots/current/$name"
  if [[ ! -f "$current" ]]; then
    echo "Missing current capture $current" >&2
    exit_code=1
    continue
  fi
  echo "== $name =="
  CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift scripts/image-diff.swift "$baseline" "$current" 0.5 || exit_code=1
done
exit $exit_code
