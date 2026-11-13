# Developer cleanup in 0.8.2

Version 0.8.2 adds the following workflow.

## Caches and Derived Data

Inspect developer caches, expand a location, and choose **Review contents**. This keeps the cache root. For Xcode Derived Data it also keeps each project's container and reviews its children (Build, indexes, logs, and package storage) independently. A blocked package checkout does not discard verified build folders from the same review.

Whole-folder review is still available after a complete measurement. Review performs a fresh complete traversal within 45 seconds and 250,000 entries per folder, with a shared deadline for the batch. The previous separate four-level metadata probe is gone. Permission errors, source-control metadata, sensitive data, changed identities, and incomplete traversals remain blockers. Git tracking failures inside a repository also block review.

The review lists excluded items and their specific reason. Use **Browse smaller folders** or correct the named folder's access, then review again. Closing Xcode/builds/package managers prevents them from recreating or changing files during cleanup. No cache is selected or moved automatically.

## Find large project folders

Open Developer → Projects and choose **Find build folders**. Select a parent of your workspaces. Results are ranked largest first, with filters for node_modules, 100 MB+, and 1 GB+. Each row names its workspace and path. Select candidates across workspaces, then review together.

Discovery searches up to 12 levels, 10,000 directories, 100,000 names, 300 workspaces, and one million measured entries within 90 seconds. It does not follow directory symlinks or cross filesystem boundaries, enter installed applications, or recurse into dependency/build candidates after measuring them. Limits, cancellation, and unreadable locations are reported. This is bounded discovery, not a claim that every project on the Mac was found.

node_modules and virtual environments require reinstalling dependencies. Name-based candidates such as build, dist, and target can contain work worth keeping; inspect them first. This reclaims disk space after Trash is emptied; it does not increase RAM.

## Emulators

Open Developer → Devices and inspect:

- **Android:** Quick Boot snapshot folders can move to Trash. The AVD user-data disk and system images remain. All Android emulators must be closed; process checks run during review and immediately before the move. A missing or failed process snapshot blocks cleanup. The next launch requires a cold boot.
- **Apple simulators:** shut-down devices can be permanently deleted through `simctl`, after typing DELETE in the confirmation sheet. The app lists the device name, runtime, state, and identifier, then re-reads its state immediately before deletion. Running, unknown, or disappeared devices are refused. Installed test apps/data are lost; shared runtimes remain. Xcode setup must be completed first; inventory never initiates Xcode's first-launch installation.
- Shared iOS runtimes and Android system images remain managed in Xcode Settings and Android Studio's SDK Manager.

## Results, recovery, and updates

Normal cleanup results include **Restore to original folder**, provided the Trash copy exists and its destination is free. Filesystem work runs off the UI thread. Moving to Trash is distinguished from observed available-space changes; APFS sharing and unrelated activity affect those measurements.

Settings → Updates (also available in the app menu) checks the official public GitHub release only on request. It opens release notes/downloads; it never silently installs an app or uploads scans.

## Validation and remaining limits

Regression fixtures cover deep caches, nested source manifests, mixed eligible/blocked batches, cache aliases, nested large node_modules, simulator state changes, Android process checks, and release URL/version validation. Device deletion tests inject command results; they never delete real devices. No real development folders are removed during verification.

Folder-tree context inspection was moved off the main thread. This removes a concrete source of UI stalls; the previously reported intermittent freeze still needs a captured hang before it can be declared resolved.


## Expanded cache coverage

Nuke Sweep also measures Yarn, Bun, Deno, uv, Poetry, Cargo registry, Maven, NuGet, CocoaPods, Hugging Face, Xcode device-support and simulator caches. These are review candidates, not automatic deletions. Re-downloading large model caches can be expensive, so review them before moving.

## Docker volumes

Docker → Volumes is a read-only inventory of the selected context. Nuke Sweep never prunes or removes volumes, because they can contain databases and user data. Use Docker deliberately for volume management.


## Project kinds

Project discovery recognizes JavaScript/TypeScript (including Bun, pnpm and Yarn lockfiles), Deno, Rust, Swift, Go, Python (including uv and Poetry lockfiles), Flutter/Dart, Java/Kotlin Gradle or Maven, and .NET workspaces. New scope presets cover Deno, Flutter, JVM and .NET projects. Detection is name-based evidence, not proof that an artifact is disposable.


Projects are grouped by workspace with rebuild guidance for each detected kind. The guidance is generic and may need adjustment for your package manager or custom build; it is not executed by Nuke Sweep.


## Possible active processes

Project groups can show a green “Possibly active” label. **Check activity** combines command-line matches, the current working directories of listening TCP processes, and the working directories of common development processes (all via read-only lsof). This is still a heuristic: it can miss processes with relative working directories, IDE helpers that do not expose the project path, non-listening processes and permission-hidden entries. It is not a reason to delete or keep anything by itself.
