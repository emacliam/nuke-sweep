#!/bin/zsh
set -eu
cd "${0:A:h:h}"

PID=$(pgrep -x Nuke | head -1 || true)
if [[ -z "$PID" ]]; then
  echo "Nuke Sweep is not running. Launch it, reproduce the freeze, then run this again." >&2
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$HOME/Desktop/Nuke-Sweep-hang-$STAMP"
mkdir -p "$OUT"

{
  date
  echo "pid=$PID"
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "dist/Nuke Sweep.app/Contents/Info.plist" 2>/dev/null || true
  ps -o pid,ppid,pcpu,pmem,state,etime,command -p "$PID" 2>&1 || true
} > "$OUT/summary.txt"

# Capture the main thread and process stacks while the freeze is happening.
/usr/bin/sample "$PID" 10 -file "$OUT/sample.txt" 2>&1 || true
/usr/bin/spindump "$PID" 5 -o "$OUT/spindump.txt" 2>&1 || true
/usr/bin/top -l 1 -pid "$PID" > "$OUT/top.txt" 2>&1 || true
/usr/bin/vm_stat > "$OUT/vm_stat.txt" 2>&1 || true
# --info --debug is required: Logger .info and .debug entries are not persisted to
# the default level, and those carry the scan/cleanup breadcrumbs worth having.
/usr/bin/log show --last 10m --predicate 'process == "Nuke"' --style compact --info --debug > "$OUT/log.txt" 2>&1 || true
/usr/bin/log show --last 10m --predicate 'subsystem == "com.zyncraft.nukesweep"' --style compact --info --debug > "$OUT/breadcrumbs.txt" 2>&1 || true
/usr/sbin/system_profiler SPHardwareDataType > "$OUT/hardware.txt" 2>&1 || true

echo "Wrote diagnostics to $OUT"
echo "Review the files for local paths before sharing. sample.txt and spindump.txt are the important ones."
