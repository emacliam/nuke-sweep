# UI snapshots

`scripts/capture-snapshots.sh` captures three deterministic pages in light and dark appearance using `--capture-fresh` so saved workspace state cannot change them:

- AI assist settings, off and on with a deterministic local provider.
- Files empty state (page argument `Storage`).
- Projects empty state.
- History with deterministic activity rows.
- Growth with two deterministic scans.
- Processes with fixed processes and listening ports.
- Developer with four fixed cache measurements and no saved scopes.
- Docker with fixed usage rows and volumes.

The enabled AI page uses `--demo-ai`, a non-persisting local-only provider configuration. History, Growth, Processes, Developer and Docker use `--demo-fixtures`, which seeds in-memory activities, scans, processes, ports, cache measurements, Docker usage and volumes with fixed dates. Demo mode disables session persistence, so it cannot overwrite saved data. It also skips live process/port/Docker refreshes so fixtures are not replaced.

Pages with live storage or last-cleanup timestamps are intentionally not captured because they are not deterministic. `scripts/check-snapshots.sh` captures again and compares against `snapshots/baseline` with a 0.5% pixel tolerance. The cursor is warped to the top-left before each launch so chart hover state is stable; the tolerance covers text-caret blink and anti-aliasing.

```sh
./scripts/capture-snapshots.sh --bless   # accept current UI as the baseline
./scripts/check-snapshots.sh             # visual regression check
```

The comparison uses `scripts/image-diff.swift` (AppKit/CoreGraphics), reports the percentage of differing pixels and a maximum channel delta, and fails on size mismatch or more than the tolerance. The current set is eighteen images: nine states in light and dark. The tolerance covers text-caret blink and chart anti-aliasing on otherwise stable pages.

Snapshots are local only. GitHub macOS runners do not provide a reliable GUI session for this check, so CI does not run it automatically.
