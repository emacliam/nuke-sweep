#!/bin/zsh
# Main-thread latency gate.
#
# Builds a synthetic tree, drives the app through a fixed scan/navigation
# itinerary with the responsiveness recorder on, then asserts the recording
# against a budget. Deterministic enough to compare across builds, which is what
# makes it a gate rather than a measurement.
#
# Usage: ./scripts/check-latency.sh [--files N] [--seconds N]
set -eu
cd "${0:A:h:h}"

FILES=20000
SECONDS_BUDGET=25
DUPLICATE_GROUPS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files) FILES="$2"; shift 2 ;;
    --seconds) SECONDS_BUDGET="$2"; shift 2 ;;
    # Adds N pairs of identical files and a duplicate comparison to the itinerary:
    # the workload the freeze was originally reproduced with.
    --duplicate-groups) DUPLICATE_GROUPS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

APP="${NUKE_LATENCY_APP:-$PWD/dist/Nuke Sweep.app}"
[[ -d "$APP" ]] || { echo "Build the app first: ./scripts/build-app.sh" >&2; exit 1; }

# A headless CI runner has no window server session; the app cannot render there.
if ! /usr/bin/pgrep -q WindowServer 2>/dev/null; then
  echo "SKIP: no window server session; latency gate needs a rendering context."
  exit 0
fi

TREE=$(/usr/bin/mktemp -d /tmp/nuke-latency-tree.XXXXXX)
ARTIFACTS=$(/usr/bin/mktemp -d /tmp/nuke-latency-report.XXXXXX)
REPORT="$ARTIFACTS/report.json"
LOG="$ARTIFACTS/run.log"
BENCH_PID=""
cleanup() {
  if [[ -n "$BENCH_PID" ]]; then
    /bin/kill -KILL "$BENCH_PID" 2>/dev/null || true
    wait "$BENCH_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TREE" "$ARTIFACTS"
}
trap cleanup EXIT

echo "== Fixture: $FILES files under $TREE =="
/usr/bin/python3 - "$TREE" "$FILES" "$DUPLICATE_GROUPS" <<'PY'
import os, sys
root, count, groups = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
# Each group is two files with identical, group-unique contents, so the finder
# has to confirm every pair by reading them rather than rejecting on size.
for index in range(groups):
    directory = os.path.join(root, "dupes-%03d" % (index // 200))
    os.makedirs(directory, exist_ok=True)
    payload = (b"group-%08d-" % index) * 400
    for copy in ("a", "b"):
        with open(os.path.join(directory, "pair-%05d-%s.dat" % (index, copy)), "wb") as handle:
            handle.write(payload)
# A wide, shallow-ish tree with varied file sizes: the shape a cache directory
# actually has, so the scan exercises enumeration rather than one deep walk.
per_dir = 50
for index in range(count):
    directory = os.path.join(root, "group-%03d" % (index // per_dir), "sub-%02d" % (index % 7))
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "file-%05d.bin" % index), "wb") as handle:
        handle.write(b"\0" * (1024 * (index % 16 + 1)))
print("fixture written")
PY

EXTRA_ARGS=()
if [[ "$DUPLICATE_GROUPS" -gt 0 ]]; then EXTRA_ARGS+=(--bench-duplicates); fi

echo "== Run: ${SECONDS_BUDGET}s itinerary =="
"$APP/Contents/MacOS/Nuke" \
  --measure-ui "$REPORT" \
  --bench-scan "$TREE" \
  --bench-seconds "$SECONDS_BUDGET" \
  $EXTRA_ARGS \
  --capture-fresh \
  --without-status-item \
  >"$LOG" 2>&1 &
BENCH_PID=$!

# The app terminates itself at the end of its itinerary; allow a margin.
DEADLINE=$((SECONDS_BUDGET + 20))
WAITED=0
while /bin/kill -0 "$BENCH_PID" 2>/dev/null && [[ $WAITED -lt $DEADLINE ]]; do
  /bin/sleep 1
  WAITED=$((WAITED + 1))
done
if /bin/kill -0 "$BENCH_PID" 2>/dev/null; then
  echo "FAIL: the app did not finish its itinerary within ${DEADLINE}s (it may be hung)." >&2
  /bin/kill -KILL "$BENCH_PID" 2>/dev/null || true
  exit 1
fi

if ! wait "$BENCH_PID"; then
  BENCH_PID=""
  echo "FAIL: the app exited unsuccessfully during the latency itinerary." >&2
  /bin/cat "$LOG" >&2
  exit 1
fi
BENCH_PID=""

[[ -s "$REPORT" ]] || { echo "FAIL: no latency recording was written." >&2; /bin/cat "$LOG" >&2; exit 1; }
if [[ -n "${NUKE_LATENCY_REPORT:-}" ]]; then
  cp "$REPORT" "$NUKE_LATENCY_REPORT"
fi
/usr/bin/python3 scripts/check-ui-latency.py "$REPORT" --max-p95 100 --max-ms 500 --require-scan
