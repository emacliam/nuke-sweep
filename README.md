<p align="center"><img src="website/assets/app-icon.png" width="112" alt="Nuke Sweep app icon"></p>
<h1 align="center">Nuke Sweep</h1>
<p align="center">Make room for what’s next.</p>
<p align="center">A native macOS cleanup and resource utility by Zyncraft.</p>
<p align="center"><a href="https://sweep.zyncraft.com">Website</a> · <a href="https://github.com/emacliam/nuke-sweep/releases/latest">Download</a> · <a href="#install">Install</a> · <a href="#build-from-source">Build</a> · <a href="https://github.com/emacliam/nuke-sweep/issues">Report an issue</a></p>

![Nuke Sweep Cleanup screen](website/assets/cleanup.png)

Nuke Sweep helps you understand what takes up space on your Mac and review what you can clear. It brings everyday caches, developer workspaces, folder inspection, cleanup receipts, and lightweight system monitoring into one native SwiftUI app.

**Version 0.8.1 is an early release.** Cleanup requires review, and backups are recommended. An intermittent freeze remains under investigation; see [known limitations](#known-limitations).

## Download

[**Download Nuke Sweep 0.8.1 for Mac**](https://sweep.zyncraft.com/downloads/Nuke-Sweep-0.8.1.dmg)

- **Requirements:** macOS Sonoma 14 or later, **Apple silicon** (M-series Mac).
- **Distribution:** Developer ID signed, notarized by Apple, and stapled for offline ticket verification.
- **No account required.** The app works with local files and keeps its scan history on your Mac.
- This download does **not** include an Intel binary. Source builds are available for development on compatible Macs.

Apple notarization checks malware and signing requirements; it is not a review of every cleanup decision or a guarantee that any file is disposable.

## Install

1. Download and open `Nuke-Sweep-0.8.1.dmg`.
2. Drag **Nuke Sweep** to the **Applications** shortcut.
3. Eject the disk image, then open Nuke Sweep from Applications.
4. Start in **Cleanup** to measure common build-up, or **Files** to select a folder.
5. Inspect the results, select the items you understand, and read the review before confirming cleanup.

If upgrading from Nuke, quit the older app and keep only the version you intend to use in Applications. The display name changed; bundle identifiers, saved preferences, URL scheme, widget kinds, and the local data folder are retained so your settings and history continue to work.

### Folder access

macOS may deny access to protected folders. Select a narrower readable folder or use **Settings → Permissions & access**. When you need protected locations, open **System Settings → Privacy & Security → Full Disk Access**, add the installed Nuke Sweep app, then quit and reopen it. The app cannot grant itself access.

Incomplete scans remain labeled, and cleanup is unavailable for incomplete locations. Granting access never selects files for removal.

### Menu bar and desktop widget

The optional menu-bar tool shows available storage, CPU, or estimated VM memory. Closing the main window keeps it running while monitoring is enabled; choose **Quit Nuke Sweep** to stop it.

For the Storage widget, launch the installed app once, then Control-click the desktop → **Edit Widgets** → search **Nuke Sweep** → choose **Storage**. macOS controls widget refresh timing; the menu-bar monitor provides current readings.

## What it does

| Tool | Use it for |
| --- | --- |
| Cleanup | Measure common application caches and Trash; review before acting. |
| Files | Inspect folder sizes, drill into a folder tree, compare complete scans, and watch a folder. |
| Developer | Inspect Xcode, npm, pip, Gradle, pnpm, Go, SwiftPM, and Homebrew caches; review project build output and custom scopes with exclusions. |
| Apps | Inspect installed applications and bundle-identifier related-file candidates. |
| Duplicates | Compare size, SHA-256, and file contents; choose a keeper before reviewing extra copies. |
| Docker | Inspect the selected CLI context and separately review supported pruning. Volumes are not pruned. |
| Devices and local models | Inspect archives, backups, simulator metadata, and known or explicitly chosen local model locations. |
| Monitor | Optional storage, CPU, and VM-memory readings, plus permission-gated alerts. |
| History | Local cleanup receipts with outcomes, export, and restoration guidance. |

![Nuke Sweep developer tools](website/assets/developer.png)

## Cleanup with context

- Nothing is selected or cleaned automatically.
- Normal file cleanup moves reviewed items to **macOS Trash**. Restore with Finder’s Put Back when available, or move the item back to its original location.
- Source-control metadata, credential stores, personal data stores, and source-looking project roots are protected by cleanup guards.
- The review rechecks identities and measurements. Unknown ownership and permission gaps remain explicit.
- **Emptying Trash and Docker pruning are permanent**, separately reviewed actions.
- Moving something to Trash normally does not free its occupied space. APFS snapshots, shared extents, and other system activity can also affect available space.

These guards reduce risk; they cannot prove that every arbitrary folder is safe to remove. Close apps or builds using selected files and review unfamiliar locations in Finder.

## Privacy

Scan history and receipts are local JSON under `~/Library/Application Support/Nuke`. The older directory name is intentional for upgrade compatibility. Records can contain local paths, process names, and CLI output. JSON export happens only when you choose an export destination.

The app has no account flow and no analytics or advertising SDK. Widgets read system metrics independently without personal scan history. Docker uses your existing CLI and selected context, which may point to a remote engine.

[Read the privacy explanation](https://sweep.zyncraft.com/privacy).

## Verify the download

Download [SHA256SUMS.txt](https://sweep.zyncraft.com/downloads/SHA256SUMS.txt) beside the DMG and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

You can also check Apple’s signature and approval:

```sh
spctl -a -t open --context context:primary-signature -vv Nuke-Sweep-0.8.1.dmg
```

Expected: `accepted`, `source=Notarized Developer ID`.

## Build from source

Requires macOS 14+, Xcode with a compatible Swift 6 toolchain, and Python 3 for ICNS packaging. There are no third-party Swift dependencies.

```sh
git clone https://github.com/emacliam/nuke-sweep.git
cd nuke-sweep
./scripts/build-app.sh
open "dist/Nuke Sweep.app"
./scripts/test.sh
```

The default build is ad-hoc signed for local development. To create a distribution build, supply your own Developer ID identity and notarization profile:

```sh
export NUKE_SIGN_IDENTITY="Developer ID Application: YOUR ORGANIZATION (TEAMID)"
export NUKE_NOTARY_PROFILE="your-notary-profile"
./scripts/build-app.sh
./scripts/build-dmg.sh
```

Do not put credentials or private keys in the repository. See [distribution notes](docs/DISTRIBUTION.md) for the signing and stapling workflow.

### Repository layout

```text
Sources/Nuke/          Native application
Sources/NukeMetrics/   Shared system measurements
Sources/NukeWidgetUI/  Widget faces and shared brand geometry
Widgets/              Embedded WidgetKit extension
Tests/                Existing safety, scanning, and behavior tests
branding/nuke-sweep/   Approved logo and app icon assets
scripts/              Build, packaging, and diagnostic helpers
website/              Static showcase deployed to Vercel
```

### Website development

The site is buildless HTML, CSS, and JavaScript with self-hosted fonts and real app screenshots.

```sh
python3 -m http.server 4173 --directory website
```

Open `http://localhost:4173`. The Vercel project uses `website` as its root. Download files are versioned, signed release artifacts; update the DMG, checksum, release copy, and links together. See [website deployment notes](website/README.md).

## Developer cleanup improvements

The upcoming 0.8.2 source build adds partial batch reviews, cache-content review, deeper project discovery with large node_modules filters, Android snapshot cleanup, and confirmed simulator deletion. See the [developer cleanup guide](docs/DEVELOPER-CLEANUP.md) for bounds, recovery, and emulator details. The public download above remains 0.8.1 until the new release is published.

## Known limitations

- An intermittent UI freeze remains unresolved. If you reproduce one, use [the hang capture guide](docs/HANG-DIAGNOSTICS.md) and review diagnostics for private information before sharing.
- Scans are bounded and do not follow symlinks or cross filesystem boundaries. Logical and allocated totals can double-count shared storage; they do not promise reclaimable bytes.
- Related application files and leftover matches are candidates, not proof of exclusive ownership.
- macOS permissions, widget discovery, and refresh schedules remain under system control.
- Intel support and privileged cleanup are not included in the distributed binary.

## Issues and source use

Report reproducible problems through [GitHub Issues](https://github.com/emacliam/nuke-sweep/issues). Include macOS version, Mac model, app version, and the steps that caused the issue. Remove private paths, credentials, and sensitive logs before posting.

Source is available for inspection. No open-source license is granted by this repository; all rights are reserved by Zyncraft Technologies. Bundled Instrument Sans is distributed under its [SIL Open Font License](website/assets/FONT-LICENSE.txt).
