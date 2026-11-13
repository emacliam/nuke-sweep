#!/bin/zsh
set -eu
cd "${0:A:h:h}"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"

echo "== Build =="
swift build --disable-sandbox --scratch-path .build

echo "== Tests =="
swift test --disable-sandbox --scratch-path .build

echo "== Package =="
NUKE_SIGN_IDENTITY="${NUKE_SIGN_IDENTITY:--}" ./scripts/build-app.sh
codesign --verify --deep --strict "dist/Nuke Sweep.app"
# The widget must start at the extension entry point, or the system's first
# launch of it traps. See scripts/build-widgets.sh.
nm -u "dist/Nuke Sweep.app/Contents/PlugIns/NukeWidgets.appex/Contents/MacOS/NukeWidgets" | grep -q '_NSExtensionMain' \
  || { echo "FAIL: widget is not linked with -e _NSExtensionMain" >&2; exit 1; }

echo "== Format =="
./scripts/check-format.sh

echo "== Latency =="
# Skips itself on a runner with no window server; see check-latency.sh.
./scripts/check-latency.sh

echo "CI passed"
