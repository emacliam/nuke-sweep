# Nuke Sweep brand assets

Approved flat identity: charcoal `#262B2B`, burnt orange `#C24521`, warm ivory `#FBFAF7`.

- `nuke-sweep-logo.svg`: transparent vector lockup (system font wordmark).
- `nuke-sweep-symbol.svg`: standalone vector symbol.
- `nuke-sweep-logo-transparent.png`: transparent 2048px logo.
- `icon-1024.png`: master app icon; `icon-16.png` through `icon-512.png` provide smaller representations.
- `NukeSweep.iconset` and `NukeSweep.icns`: packaged macOS icon.
- `export-brand.swift`: deterministic AppKit export source.

The application uses the same symbol geometry in `Sources/NukeWidgetUI/SweepMark.swift`. The sidebar, monitor and widgets use the two-color mark; the menu bar uses a system-tinted monochrome template.

Regenerate exports from the project root:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift branding/nuke-sweep/export-brand.swift "$PWD/branding/nuke-sweep"
python3 scripts/package-icon.py branding/nuke-sweep/NukeSweep.iconset branding/nuke-sweep/NukeSweep.icns
```

The app build copies the approved iconset through `scripts/make-icon.swift`, packages ICNS, and signs the containing bundle. Generated-image explorations are retained as design history; production builds use the clean deterministic exports.
