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
