# Nuke Sweep: notes for working on this repo

Native macOS cleanup app (SwiftUI + AppKit, Swift package, no dependencies). `PRODUCT.md` and `DESIGN.md`
describe the product and its look; `docs/DISTRIBUTION.md` covers signing, notarisation and Sparkle updates.

## Hard safety rules (also while developing)

1. **Never clean, trash, delete, hibernate or offload anything real.** Real-machine runs are read-only: scans,
   reviews that are opened and cancelled, `nuke check`, or the app without confirming anything.
2. Flows that change files run only in tests or fixtures: fixture folders under `/tmp/nuke-*`, a stand-in for
   Trash (`OffloadEngine.offload(..., trash:)`), a disk image mounted for the test (see `OffloadTests`).
3. Tests must not create anything under the real home folder. Pass a temporary home instead.
4. No `sudo`, ever. Fixes that need admin rights are shown as a command for the person to run.
5. Every deletion goes through review: `ReviewPlanner` checks each item, the seal is re-verified at move time
   (FSEvents vouches for unchanged folders; anything else is read and compared in full).
6. Rebuildable items (caches, dependencies, build output) are deleted outright with `TreeRemover`; the person's
   own files only ever go to Trash.
7. Don't edit `~/Library/Application Support/Nuke` or the production app's preferences by hand. The development
   build (`scripts/build-development.sh`) keeps its own data under `Nuke Sweep Development`.

## Commands

```sh
swift build && swift test                           # all tests must pass
scripts/build-development.sh                        # dist/Nuke Sweep Development.app, isolated data
scripts/snapshot.sh [OUT_DIR] ["Find space" ...]   # the app renders its own pages, light and dark
```

The development app takes `--snapshot DIR --snapshot-page <Page raw value> --appearance dark|light
--quit-after-snapshot` to draw its window (and any open sheet) to PNGs without screen-recording permission.
`--demo-fixtures` shows demo data and never scans the real disk.

## Releasing

`VERSION` holds the version and build number. `scripts/build-app.sh` then `scripts/build-dmg.sh` (with
`NUKE_SIGN_IDENTITY` and `NUKE_NOTARY_PROFILE`) produce a notarised DMG; `scripts/verify-release.sh --strict`
checks it; `scripts/generate-appcast.sh` signs the update feed. Publishing (pushing, GitHub releases, merging)
needs the owner's explicit go-ahead each time.

## Credits

Several features adapt ideas and wording from Major Tom (https://github.com/tjlondon-npauctions/majortom),
MIT License, Copyright (c) 2026 Tom Jordan. Keep that notice on code derived from it.
