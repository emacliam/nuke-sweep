# Localization

Nuke Sweep ships English (`en`) and a partial Spanish (`es`) catalogue. The
Spanish catalogue covers first-run setup, the main storage check, Personal
Files, and the main labels in Trash review and receipts. Other keys fall back
to the English source text.

## How it works

SwiftUI's `Text`, `Button`, `Toggle`, `Label`, `Picker` and friends take a
`LocalizedStringKey`, not a `String`. A literal written at a call site is
therefore **already a translation key** — it just resolves to itself while no
catalogue contains it. No `NSLocalizedString` wrapper is needed at those sites.

`Resources/<locale>.lproj/Localizable.strings` is copied into the app bundle's
`Contents/Resources` by `scripts/build-app.sh`, where `Bundle.main` finds it.
`CFBundleLocalizations` in the generated `Info.plist` declares what ships.

Verify a locale without changing system settings:

```bash
"dist/Nuke Sweep.app/Contents/MacOS/Nuke" -AppleLanguages '(es)'
```

## Regenerating the key inventory

```bash
python3 scripts/extract-strings.py --write Resources/en.lproj/Localizable.strings
```

The script only matches initializers whose first argument is a
`LocalizedStringKey`. It reports interpolated literals separately rather than
pretending to handle them — see the gaps below.

## Writing localizable UI

Shared components take `LocalizedStringKey`, so a literal localizes for free:

```swift
SectionTitle(title: "What matters here")
Notice(text: "Nothing is selected.", symbol: "info.circle")
```

Text assembled at runtime — a folder name, a byte count, a provider's error —
must **not** be looked up as a key. Use the `measured` factories:

```swift
SectionTitle.measured(title: app.name, detail: app.version)
Notice.measured(providerError, symbol: "exclamationmark.triangle")
BusyLine.measured(progressText)
```

These are static factories rather than overloaded initializers on purpose.
Competing initializers on a component used at ~90 call sites multiply the type
checker's work enough to push large view bodies past its time limit, and the
Swift compiler fails outright rather than merely slowing down. `StorageToolbar`,
`StorageSummaryBar` and `VolumesMenu` were extracted from `StorageView` for the
same reason.

For a sentence that embeds a value, build it with `String(localized:)` and
`String(format:)` so translators get a whole sentence with a placeholder, not
fragments. `StorageView.partialScanNotice` is the worked example.

## What is covered

- 750 keys from SwiftUI view literals and `String(localized:)` call sites.
- The shared components: `SectionTitle`, `Notice`, `EmptyPanel`, `BusyLine`.
- Navigation: `Page.title` and `Page.localizedSubtitle` carry translatable names
  separately from `Page.rawValue`, which stays stable because the saved workspace
  persists it. `CandidateAssessment.State` uses the same split.
- Model-layer content: `CleanupEvidence` details and rebuild advice,
  `RebuildCost`, `BackupCoverage`, `CandidateAssessment`, `StoragePressure`.
- Plural rules via `Resources/en.lproj/Localizable.stringsdict`, reached through
  the `Plural` helper. Counted phrases no longer use `count == 1 ? "" : "s"`,
  which is right for English and wrong for most other languages.

## Known gaps

1. **84 interpolated literals.** `Text("Context: \(name)")` is a key containing a
   runtime value, so it cannot be translated. Each needs `String(format:)` over a
   `String(localized:)` format string. They are concentrated in `MonitorViews`,
   `ContentView` and `InsightViews`; run `scripts/extract-strings.py` to list the
   current count. Prose where word order matters should be converted first —
   label-plus-value pairs degrade more gracefully.
2. **Spanish coverage is partial.** The catalogue has 220 keys. Use
   `-AppleLanguages '(es)'` to check translated flows and identify English
   fallback in the remaining screens.
3. **No pseudolocalization pass.** Nothing checks that a longer translation fits;
   German and Finnish strings routinely run 30-40% longer than English.
4. **Date and byte formatting** goes through `ByteCountFormatter` and
   `Date.formatted()`, which localize themselves — but the surrounding sentences
   often do not, which is the same problem as (1).

A locale is supportable once (1) is closed and (3) has been run at least once.
Until then, treat `es` as a test fixture rather than a shipped language.
