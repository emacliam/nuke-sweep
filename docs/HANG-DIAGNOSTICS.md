# Freeze diagnostics

The intermittent Nuke Sweep freeze is still uncertified. Reproduce it, then capture evidence **while the app is frozen**:

```sh
./scripts/capture-hang.sh
```

The script writes `~/Desktop/Nuke Sweep-hang-<timestamp>/` containing:

- `summary.txt` — PID, version, process state and elapsed time;
- `sample.txt` — 10-second main-thread and process sample (the most important file);
- `spindump.txt` — system-wide stacks during the freeze;
- `top.txt`, `vm_stat.txt` — resource state;
- `log.txt` — the last 10 minutes of Nuke Sweep unified-log entries;
- `hardware.txt` — machine model.

## What to do

1. Launch Nuke Sweep normally and use it until the slow interaction happens.
2. Without quitting the app, run the script in Terminal.
3. Review the folder for local paths before sharing. `sample.txt` and `spindump.txt` are the files needed to diagnose the hang.
4. Share the folder (or just the two samples) with the developer.

Do not force-quit Nuke Sweep before capturing; the sample attaches to the live process.

## What this establishes

A sample shows where the main thread was at that moment. It can distinguish a blocked filesystem call, a main-thread layout loop, a lock wait and an idle app waiting for the system. A single sample is not proof of the root cause; repeated captures of the same slow interaction are much stronger.

`spindump` can require additional permissions for kernel stacks; partial output is still useful.

## Automatic capture (opt-in)

Settings → General → **Capture hang diagnostics** enables a local watchdog. It pings the main queue once per second. If the main thread does not answer for two seconds, it writes:

- `metadata.json` with app version, build, OS, PID, timestamp and stall duration;
- `sample.txt` from `/usr/bin/sample` on the running process;
- the last 10 reports are retained under `~/Library/Application Support/Nuke/Diagnostics/`.

It is off by default and does not use the network. The files may contain local paths, so review them before sharing. Open the folder from the same settings section. The same section also opens macOS crash reports for this user.

**Export diagnostics** writes a local JSON support bundle with app/system versions, counts, provider names/models (no keys or base URLs), schedule names/frequencies (no paths), and a hang-report count. It contains no file contents or absolute folder paths. Review the JSON before sharing.

The setting is **not** a fix for the freeze; it makes the next occurrence diagnosable. The manual `scripts/capture-hang.sh` remains available for a hang that happens while the watchdog is off or for a longer sample.

To share a small report, turn on **Offer to share failure reports** in Settings → General. After a hang, return there and choose **Review latest hang report**. After a cleanup with failed items, the result sheet offers **Review failure report**. The preview shows the exact text passed to the macOS share menu. You choose the destination.

The report includes the event, time, app build and macOS version, plus hang duration or cleanup item counts. Stack samples and detailed receipt errors stay in the separate local diagnostics tools.
