---
name: Nuke Sweep
description: A warm, compact native macOS cleanup and resource utility.
colors:
  rust: "rgb(76% 27% 13%)"
  forest: "rgb(22% 40% 33%)"
  ink: "rgb(15% 17% 17%)"
  secondary: "rgb(40% 42% 42%)"
  paper: "rgb(98.5% 98.1% 96.9%)"
  rail: "rgb(95% 94.6% 92.6%)"
  line: "rgb(88% 88% 85%)"
  warning: "rgb(65% 38% 4%)"
  error: "rgb(72% 16% 13%)"
  white: "#FFFFFF"
  treemap-rust: "rgb(65% 22% 10%)"
  treemap-forest: "rgb(25% 36% 32%)"
  treemap-slate: "rgb(29% 36% 44%)"
  treemap-clay: "rgb(47% 30% 24%)"
  treemap-plum: "rgb(39% 33% 43%)"
  widget-dark-background: "rgb(12% 13% 13%)"
  widget-dark-accent: "rgb(97% 61% 43%)"
typography:
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "23px"
    fontWeight: 600
    letterSpacing: "-0.4px"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "15px"
    fontWeight: 600
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "11px"
    fontWeight: 400
rounded:
  control: "7px"
  surface: "12px"
  search: "6px"
  notice: "8px"
spacing:
  main: "24px"
  section: "20px"
  surface: "22px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "10px 15px"
  button-quiet:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "9px 12px"
  surface:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.surface}"
    padding: "{spacing.surface}"
  search:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.search}"
    padding: "8px"
    width: "185px"
---

# Design System: Nuke Sweep

## Overview

Nuke Sweep uses warm neutral surfaces, a restrained rust accent, and compact native macOS controls. The supplied nine web screenshot collections inform the visual direction; they are references, not shipped assets. The implementation is code-led in SwiftUI and AppKit.

A persistent sidebar frames scrollable work areas. Measurements, paths, and review actions carry the hierarchy. The native SF system font keeps the utility familiar on macOS; no decorative illustrations are used.

**Key Characteristics:**

- Warm paper and rail backgrounds with white grouped surfaces.
- Rust navigation and storage emphasis; forest readiness and watch status.
- Compact native type, controls, symbols, and explicit review surfaces.

## Colors

The frontmatter preserves the exact RGB channel values from SwiftUI's `Theme`, rather than rounded hex approximations.

### Primary

- **Rust:** app mark, selected section underline, storage usage strip, tint, and attention icons.

### Secondary

- **Forest:** available storage, readiness indicators, and active watching status.

### Neutral

- **Ink:** primary text and primary button fill.
- **Secondary:** supporting text, metadata, and quiet icons.
- **Paper:** main workspace background.
- **Rail:** sidebar, table headers, and softly tinted notice surfaces.
- **Warning:** amber for partial, stopped, missing, and access warnings; it is distinct from rust interaction emphasis.
- **Error:** native-leaning red for failed cleanup outcomes; not used for brand emphasis.
- **Line:** separators and thin container borders.
- **White:** grouped surfaces, selected navigation background, and primary button text.

WidgetKit containers adapt to system appearance: light uses paper and rust, while dark uses the widget-specific background and lighter warm accent in frontmatter. Widget text uses native primary/secondary semantic colors. This adaptive widget palette does not change the main window theme.

Native error red appears for resource errors. One overview process icon uses a muted indigo; neither is a reusable custom theme token.

## Typography

**Display and Body Font:** native macOS SF system font, selected through SwiftUI `.system`. The CSS font stack in frontmatter is a portable representation for documentation previews.

The page heading uses the headline role. Section headings use the title role; content is generally 12 points, with 10–11-point metadata and native table headers. Metrics use 21–22-point medium weight. The sidebar wordmark uses 18-point semibold system type with −0.4 tracking beside the approved two-color Nuke Sweep mark. SwiftUI supplies native line heights.

Monospaced digits stabilize measurements. Monospaced type is reserved for selected technical paths and Docker context text; ordinary path labels may retain the body font.

## Layout

Minimum window size is 980×650 points; default is 1180×790. The sidebar is fixed at 202 points and separated by a one-point rule. Four core destinations remain visible above bottom Settings and local-machine information; it has no tool search or expandable groups.

The main workspace has contextual section tabs and 24-point content padding. A 40-point top bar appears only when it carries a control: a back path for deep Developer pages, the Files or Processes filter, and refresh. The persistent disk-activity bar sits above page content, outside its scroll region, and owns the single Stop for active and queued disk jobs; pages report only the last outcome, not a second live status. There is no global footer. Cleanup shows the latest receipt as a compact last-cleanup line with item count, observed free-space delta, and a route to History. Most pages scroll vertically with 20-point section gaps. Files and Apps instead occupy the available height: their native tables scroll independently, Files keeps its review actions below the table or tree, and Apps has a separate scrolling inspector. Queued review preparation has a separate Cancel review action. The native window minimum bounds layout rather than web breakpoints.

## Elevation & Depth

Flat tonal layering and thin borders define groups. White surfaces sit against warm paper, with the rail tone supporting navigation and notices. Custom components have no shadows or ornamental gradients. Native sheets and alerts retain macOS presentation.

## Shapes

Controls and selected navigation rows share gently rounded corners. Grouped surfaces use the larger surface radius. Search and notice containers use their own smaller radii. Some list containers and the app mark use nine-point corners; the overview developer inset uses ten points. Circular dots communicate selection, storage legend, and readiness.

## Components

### Buttons

Compact and restrained. Primary buttons use ink fill, white 12-point semibold labels, and the primary padding token. A pressed primary uses 80% fill opacity. Quiet buttons use white fill, an ink 12-point medium label, and a one-point line border; pressing changes their fill to the line color. Both custom styles reduce the whole control to 40% opacity when disabled. No custom hover or focus animation is defined; keep native keyboard behavior.

### Cards / Containers

`Surface` groups related content with white fill, a one-point line border, surface corners, and surface padding. Notices use the rail at 65% opacity, rust symbols, 11-point secondary text, 15-point padding, and notice corners. Empty states use an SF Symbol, a 21-point medium title, and explanatory copy constrained to 420 points.

### Inputs / Fields

Search uses a white plain text field, a magnifying-glass symbol, an 11-point system font, a thin line border, and the search geometry in frontmatter. Top-bar filters are scoped to Files browsing or Processes. Apps has its own native rounded-border app filter. Segmented sorting and focus appearance follow macOS.

### Navigation

Sidebar rows use a 13-point label, a 19-point symbol slot, 12-point horizontal and vertical padding, and seven-point corners. Selection uses semibold ink on white with native accessibility selected traits. Cleanup, Files, Apps, and History are the core destinations; Settings sits at the bottom. Cleanup tabs are Quick scan, Developer, and Trash. Projects, Docker, Devices & Xcode, and Local models keep Developer highlighted and expose a back control in the top bar. Files tabs are Browse, Duplicates, Growth, and Watchlist. Settings holds Menu bar, Permissions, Alerts, Widgets, Startup, Processes, Updates, and AI assist. Tabs use 12-point type, rust selection text and a two-point rust underline. Developer offers Projects, Docker, and Devices & Xcode shortcuts; Local models appears when inventory/custom roots exist and is always reachable through More → Inspect local models. Older standalone page implementations are not additional sidebar destinations.

### Files Table

Files uses the complete measured item set in a native virtualized Table without a 300-row rendering cap; scan bounds still apply. Columns hold an unselected-by-default checkbox, name/SF Symbol, logical size, and a labeled contextual actions menu for use, reveal, and scan-inside. Incomplete rows append “+”, use the warning amber, and disable selection. Filtering has its own empty state. Selection count and Review selected remain below the scrolling table; review rechecks candidates. Stopped, scan-limit, and access-gap notices give distinct recovery guidance. The optional Storage map starts collapsed and persists its disclosure state.

### Files Tree

A Table / Tree segmented control switches the same measured root. Tree renders the first level from the existing scan and measures exactly one more level when a folder is disclosed (12,000 entries or six seconds), so switching modes is instant and drilling stays bounded. Rows show disclosure, an unselected checkbox, folder/file symbol, name, logical size with partial markers, a loading indicator, and an explicit Empty label. A partial child scan is marked amber and appends “+”.

Selecting a folder includes its current contents when review runs; selecting an ancestor and descendant together is prevented by normalizing the selection, so the review never double-counts or moves the same subtree twice. Manual scans, root changes, and completed cleanups reset expansions; periodic automatic refreshes do not collapse the tree. Typing a search returns to Table. Developer cache rows and Find space candidates open their measured folder as a tree root.

Rows carry compact evidence badges: known cache, dependencies, build output, project source, protected, or no badge for unknown. A project/source or protected badge disables selection before review. The same tree is used inside a custom scope with two extra guards: child scans skip the scope's excluded paths, and a folder that is or contains an excluded path is disabled with an amber warning. Scope trees keep their own expansion state and are reset when the scope definition or measurement changes.

### Developer Cache Rows

The four primary caches remain visible; additional built-in caches (pnpm, Go, SwiftPM, Homebrew) sit under a collapsed “More built-in caches” disclosure so custom scopes stay reachable. Compact rows show an SF Symbol, cache name, measured size/state, and disclosure chevron. Each has 16-point vertical padding and a divider. One expanded row reveals a selectable monospaced path, cleanup impact, Browse tree, and Review cleanup; details use a 34-point inset. Unknown, not-inspected, partial, and stopped outcomes remain explicit; stopped, scan-limit, and access-gap outcomes are distinguished. Partial locations append “+ · partial” and disable cleanup, with smaller-folder browsing as recovery. No automatic selections are made.

### Custom Developer Scopes

Developer remembers user-defined scopes below the built-in cache rows. Each scope has a label, a chosen folder, a policy (Cleanup after review or Inspect only) and relative excluded paths. A scope is a bookmark, not a grant: forgetting it never touches files.

Scope measurement is user-triggered, bounded to 60,000 entries or 15 seconds, and measures one level of direct children with the existing activity bar and Stop. An expanded scope uses the exclusion-aware FolderTreeView to measure deeper levels on demand, so the same exclusions apply at every depth. Excluded paths are skipped before counting or traversal, so they neither appear nor inflate the total. A folder that is, or contains, an excluded path cannot be selected; this keeps a reviewed folder move from absorbing an excluded subtree. Inspection-only scopes show disabled selection and lock-oriented detail.

Presets prefill exclusions for Node, Python, Rust, Swift/Xcode, and monorepo starting points; the user still chooses the folder and can edit everything. Scope definitions can be exported and imported as JSON; imported cleanup flags do not grant filesystem access. Cleanup scopes also require a macOS folder grant and the shared review. Rows show logical size, partial markers, and an amber “contains an excluded path” warning. The editor validates an existing folder, normalizes exclusions (no wildcards, escapes ignored), and attempts the folder grant only when cleanup is enabled. Measurements are transient; scope definitions persist locally.

### Storage Strip

Storage meters place a rust used-capacity segment beside a rail-colored remaining segment, with a three-point gap and rounded corners. The full meter is 22 points high; the Cleanup summary uses an 8-point, 170-point-wide version beside the available reading and a refresh control. Actual disk fraction determines the fill. Used, capacity, and available labels explain the measurement; an accessibility label states used and total storage.

### Cleanup Safety

Safety is a layered, evidence-based refusal system, not a claim that a scanner can prove a file is disposable. Protected home/system locations, Nuke's own bundle, incomplete measurements, changed identities, and items outside a cleanup grant are refused before review. Source-control metadata (`.git`, `.hg`, `.svn`), credential stores (`~/.ssh`, `~/.gnupg`, `~/.aws`), keychains, Mail/Messages/Calendars/AddressBook, and Photos stores are hard-blocked.

For directories, review also checks the selected folder and up to four levels below it for project evidence (`.git`, package manifests, Xcode projects, and similar). A folder that looks like a project or source root is refused as a whole, with a message to select build folders inside it. Dependency/build names (`node_modules`, `dist`, `build`, `target`, `.venv`, `DerivedData`, and similar) are exempt from the copied-manifest ban unless they contain a Git repository; this avoids treating `dist/package.json` as source. A bounded source-file probe refuses folders that contain code files without any compiled/build signature, catching source trees that have no manifest. A bounded `git ls-files` probe refuses folders containing tracked files. A marker scan that exceeds its entry/deadline bounds, cannot read a level, or exceeds the depth bound is treated as unverified and refused rather than assumed safe.

The review sheet re-measures folders, rechecks identities, shows partial/unknown states, and requires an acknowledgement. It labels each prepared item with cheap evidence (known cache, dependency, build output, git-ignored, project root, protected, or unknown) plus rebuild guidance, adds a git check-ignore probe for selected items, and warns when lsof observes open handles under a selection. A reviewed item with an open handle still requires the acknowledgement. “Export plan…” writes the dry-run JSON, including paths, sizes, evidence and warnings, without touching files. Normal file cleanup moves to macOS Trash; permanent Trash deletion is separate and requires the exact EMPTY confirmation. Receipts record outcomes and restoration guidance. These are strong guardrails, not a guarantee: arbitrary folders, copied manifests, files added during deletion, and user intent remain outside what Nuke can prove.

### Keyboard and accessibility

The Files tree supports a visible keyboard focus: up/down move, Space toggles selection, left/right collapse or expand, Return toggles a folder. Blocked and incomplete rows refuse keyboard selection. The tree exposes a hint to assistive technology. Charts retain marked values and a picker alternative. See [ACCESSIBILITY.md](docs/ACCESSIBILITY.md) for the map and known gaps.

### Docker Volumes

Docker lists volume names, drivers, scopes and mountpoints as read-only inventory. Volumes are excluded from every cleanup action. The UI states that volumes may contain databases and user data and points the user to Docker for deliberate management.

### Visual Regression

AI settings (off and on), Files, Projects, History, Growth, Processes, Developer and Docker are captured in light and dark appearance. Data pages use fixed in-memory fixtures (`--demo-fixtures`) with no session persistence and no live refresh. `scripts/check-snapshots.sh` compares current captures to baselines with a 0.5% pixel tolerance and fails on size mismatch. Baselines are versioned; current captures are ignored. This is a local GUI check, not a headless CI job.

### Diagnostics Export

Settings → Menu bar can export a local JSON support bundle. It includes app/build versions, system capacity and counts, provider names/flavors/models, schedule names/frequencies, and a hang-report count. It deliberately omits API keys, provider base URLs, absolute schedule paths and file contents. Export is user-initiated with a save panel.

### Listening Ports

Processes includes a read-only TCP listening-port inventory from `lsof`: port, address, process and PID. It is refreshed when the page opens or on demand, and the Processes search field filters by port, process or address. Permissions can hide entries; UDP is not included; a port does not prove a project is active, and no process is stopped from this view. Parsing and permission-failure behavior are unit tested; live `lsof` output is environment-dependent.

### Project Groups

Projects are grouped by workspace instead of one flat list. Each group shows its detected kind, total size, a reveal action and rebuild guidance appropriate to that ecosystem. Filters apply within each group, and each group has its own reviewed selection. Detection is name-based and remains advisory. A project can show a cautious “possibly active” hint when a running command contains its absolute path, or when a listening TCP process or a common development process has a current directory under the project root. Check activity refreshes this read-only mapping; it remains heuristic.

### Mounted Volumes

The Files toolbar lists mounted volumes with free capacity; choosing one starts the normal bounded Files scan at that root. Root, internal and external volumes are ordered predictably, hidden system volumes are skipped, and no cleanup is implied. See [VOLUMES.md](docs/VOLUMES.md).

### Scheduled Scans

Files → Schedules can schedule hourly, daily or weekly measurements for a folder. The scheduler runs only while the app is open and awake, runs one scan at a time, and saves only complete results through the existing Growth history path. It has no cleanup authority and no network path. Quiet hours and finish notifications are opt-in and local. See [AUTOMATION.md](docs/AUTOMATION.md).

### Appearance

The app follows the system appearance by default; Settings → Menu bar exposes System, Light and Dark for the main window and the menu-bar tool. Theme colors are adaptive: text and separators use system semantic colors where possible, while the cream paper, rail, surface, rust accent and status colors have explicit light and dark variants. Primary actions use charcoal in light and rust in dark with white text. The brand mark uses the primary label color so it remains visible on both backgrounds. Charts already provide labeled marks and a picker alternative; keyboard traversal and VoiceOver coverage for every custom tree remain an ongoing audit.

### AI Assist

AI assist is off by default in Settings. The page is a provider manager: local, DeepSeek, Anthropic, Gemini and any number of OpenAI-compatible endpoints. Keys are stored per provider in the login Keychain. Cloud endpoints require HTTPS; HTTP is restricted to 127.0.0.1, localhost or ::1. Providers can be added, edited, tested, switched or removed; removing a provider deletes its key. Plan can use a different provider/model from Explain. Plan proposals may add scope exclusions; exclusions only protect. Growth compares stored scans. A payload preview shows the exact metadata shape before use, and a session request log records provider, item name, outcome and latency without payloads.

Tree rows expose “Explain with AI” on hover, for unknown/source-like evidence, and in the context menu. The cleanup review sheet offers the same action for each pending item. The tree header adds **Draft with AI**: an instruction becomes a top-level selection plan, blocked/source-like items are excluded locally, and applying only checks boxes for the normal review. Settings adds Test connection, model discovery and a hard cloud-block switch. The request sends only name, relative path, size, kind, evidence label/detail, rebuild hint, Git ignore state and scope label/policy. No file contents, source, credentials, receipt paths or absolute home paths are sent. Responses are parsed into a strict category/confidence/explanation/rebuild/risks schema and shown as an advisory card; AI cannot select, run tools, move files or override a hard block. Local inference is the privacy-preserving default; DeepSeek is an explicit cloud opt-in.

### Review Surfaces

File cleanup uses a native sheet with a bounded scrollable item list and an acknowledgement toggle before the action enables. Docker cleanup uses a separate native review sheet. Process quit requests use a native confirmation alert. These surfaces repeat compact text, visible notices, and clear cancel/action placement.

### Inventory Candidates

`InventoryList` is shared by project artifacts, AI model storage, device/archive inventories, application-related files, and possible leftovers. Native checkboxes begin unselected and reset when the entry identities change. Rows use 13-point semibold names, right-aligned 12-point medium monospaced sizes, rust 10-point category/owner labels, monospaced selectable paths, and secondary explanations. Ownership and identifier matches are candidate evidence, not proof of exclusive ownership. Measurement incompleteness appends “+” to size and an explicit explanation; incomplete, nonremovable, and busy entries cannot be selected. A shared summary reports inspection completion time when available, listed sizes, and complete-location count without claiming freeable space across projects, Local models, devices, applications, and possible leftovers. Ownership & cleanup details are placed in native disclosure groups while incomplete cleanup-unavailable status stays visible. Permission gaps and inspection limits remain visible through notices. Finder reveal and file-use inspection accompany each candidate. Review selected is disabled without a selection and routes through the existing cleanup review.

### Growth Comparison

Native folder and baseline pickers precede a segmented choice between files/folders and inferred categories. A compact table uses nine-point uppercase labels, right-aligned Before/Latest/Change columns, 12-point content, and monospaced digits. Positive deltas use rust; nonpositive deltas use forest and explicit signs distinguish growth and reduction. Empty and one-scan states explain the next scan needed. Notices state same-root comparison, excluded partial scans, category inference, and logical-byte limitations; these are comparisons of saved scans, not reconstructed past activity.

### Application Master / Detail

Apps uses a native Table of inspection buttons with alternating row backgrounds disabled, a rounded-border filter, and a count inside a rail container (190-point minimum, 220-point ideal, 250-point maximum width; 12-point padding and nine-point corners). A 24-point gap separates a flexible, independently scrolling inspector. Each AppChoiceRow keeps ink text and marks the inspected app with a pale rust background (eight-percent opacity), rust checkmark, and four-point corners. Rows have seven-point horizontal and five-point vertical padding. Their accessibility label is “Inspect” plus the app name, with a selected trait for the inspected app. Inspection focus is separate from cleanup checkboxes. Selecting an app loads identity, version, bundle identifier, inventory candidates, and coverage/permission notices. Possible leftovers retain an honest empty state. No cleanup candidates are preselected; failures do not trigger automatic privilege elevation.

### Startup and Device Inspection

Startup rows show scope, owner, executable path, and observed state in the existing compact type hierarchy. An amber warning labels missing executables. Bundled helpers explicitly retain unknown registration/enabled status; the Login Items settings action opens macOS's authoritative controls. Eligible plist removal uses review, without implying it unloads a running job. Device inspection shares inventory rows and notices; the global activity bar owns Stop, and copy explains that cancellation stops file traversal while a CLI call can take up to 20 seconds. Simulator/runtime management points to Xcode. Backups and archives are presented as recovery data requiring review.

### Duplicate Groups

Each group displays count and extra logical bytes, a native “Keep this copy” picker, selectable file paths, Finder reveal, and “Review other copies…” as a quiet action. The picker identifies the retained copy; only the other copies enter cleanup review, with content rechecked before cleanup. Notices explain bounded coverage and that identical contents can have different purposes. The global activity bar offers Stop during inspection. No recovered-space guarantee is inferred from logical duplicate bytes.

### Open-file Context Sheet

“Processes using this location” is a native sheet with 28-point padding, a 620-point width, a 19-point semibold title, a selectable monospaced location, and Done. A bounded 320-point-high scrolling list pairs process/PID with observed paths. Busy text and the report notice expose the bounded, permission-limited observation. An empty result does not prove a file is unused.

### Menu-bar Monitor and Settings

The native AppKit status item retains the template asterisk and 11-point monospaced-digit reading. A persisted native toggle optionally adds Nuke’s name; Icon only provides the smallest active footprint. Paused and Sleeping states remain explicit, with accessible naming and help. `StatusBarController` owns a transient hosted popover, while `LiveMonitor` owns asynchronous live sampling and history. While the popover is shown, local and global mouse-down monitors dismiss it on left, right, or other outside clicks; local events continue to their intended control. Clicks within the popover stay interactive, and its own status button retains native toggle behavior. App resignation also dismisses it. Closing removes the event monitors and observer. Manual checks in the final normal signed app observed: Refresh inside preserves the popover; clicking Nuke’s File menu dismisses it and opens that menu; clicking Finder’s File menu dismisses it; Escape dismisses it.

The 330-point popover uses 20-point padding and the incumbent paper/ink palette. Its header pairs Nuke’s mark/name with Live, Paused, or Sleeping text and accessible pause/resume and refresh icons; refresh is disabled while paused or sleeping. Available storage becomes the primary 29-point measurement, with capacity context and a native rust used-capacity bar. An 18-point CPU/VM pair is separated by a thin rule. Updated time and interval precede recent CPU history, retained-reading caveats, and the VM definition. A compact last-sweep line appears when a receipt exists. Find space uses the ink primary action beside Processes and Scopes; a compact footer exposes Open Nuke, settings, and Quit with accessible icon labels.

Settings use existing grouped surfaces with native toggles and a storage-threshold stepper. Alerts are optional, initially off, require macOS notification permission, and are disabled when monitoring is off. Visible status explains permission denial or scheduling failure. Sustained CPU means three samples at or above 85%; alerts are limited to one per hour. Closing the window keeps enabled monitoring running; Quit stops it. Monitoring never initiates cleanup. The popover shows Updated time, a recent CPU chart of up to 25 samples, and Pause/Resume. Paused readings are explicitly identified as the last measurements. Settings also expose optional SMAppService launch-at-login registration with actual enabled, approval-required, off, unavailable, or unknown status and errors; enabling it is a user choice.

### Desktop Widgets

Version 0.8 registers only Nuke Storage in small and medium WidgetKit families. Resource widget types remain in source but are deferred and absent from the widget bundle. The app previews only the Storage face, using 174×174 points, 16-point padding, white fill, a thin border, and 18-point corners; preview dimensions are not guaranteed desktop sizes. Shared native SF faces retain the asterisk, adaptive light/dark palette, monospaced measurements, and explicit unavailable/Updated states.

Storage emphasizes available bytes, capacity context, and a native tinted usage bar. Its click opens nuke://storage. The extension reads system counters and requests its next timeline after 15 minutes; macOS controls actual timing. Refresh requests do not guarantee an immediate update. Setup copy explains Edit Widgets and local ad-hoc build discovery limits. Live CPU/memory belong to the menu bar; the widget is a timestamped snapshot.

### Storage Treemap and Native Charts

Files offers a collapsed-by-default Storage map disclosure containing an interactive logical-byte treemap in a 260-point-high plot. It shows up to the 24 largest positive-sized items and aggregates the remainder; zero-byte items stay in the list. Its five dark categorical tones are the treemap-specific tokens in frontmatter, with white 11-point labels only where a tile exceeds 90×48 points. Tiles have one-point white borders; selected tiles have three-point borders. Hover help and accessibility labels expose name and exact size even when a tile is too small for text. Selecting a tile exposes exact size and applicable Reveal, Scan inside, and reviewed-cleanup actions below. Aggregate tiles have no item cleanup action. Area represents measured logical bytes, including any partialness, rather than reclaimable space.

Native Swift Charts extends Growth with a 210-point folder-size history and a diverging largest-change chart of up to ten nonzero items. History has a zero-based adaptive decimal byte-unit scale (bytes, KB, MB, or GB), rust line and points, and a selected-date rule. Joined points indicate saved-scan order; changes between scans were not observed. Change bars use rust for growth, forest for reductions, an explicit zero rule, and exact before/after/delta text. The underlying comparison table remains available. Hover and drag inspect the plots; native scan/change pickers provide keyboard access to exact values.

Recent resource history is collapsed by default in Menu bar settings. Resource history separates CPU and VM into two 140-point charts with explicit units. CPU uses a fixed 0–100% scale; VM uses zero-based decimal GB and forest marks. Each chart has its own time/value readout and keyboard sample picker, plus hover/drag inspection. Unknown readings and long sampling interruptions break line segments. History is kept in memory for the current session’s last ten minutes. A persisted native segmented control selects two, five, or ten minutes ending at the last sample, with a waiting state before a second visible sample. The menu CPU chart is a compact 70-point version with the same zero-to-100% domain, a dashed 85% alert-threshold rule, leading axis marks, and the same inspection behavior. No shared axis implies that VM bytes and CPU percent are comparable quantities.

### Permissions and Access Recovery

The permissions page retains native pickers, toggles, quiet/primary buttons, selectable folder paths, dividers, notices, and existing type and spacing. Saved folder bookmarks show either resolved access with remaining filesystem/privacy caveats or an unavailable state asking the user to choose again. Choose, retry, and forget actions do not imply that files were selected or deleted. Forget removes saved access without claiming to revoke System Settings grants.

Protected-folder guidance states that Full Disk Access is controlled by macOS and cannot be summarized as one reliably known global grant. A partial scan is not presented as an empty folder. Native actions open Full Disk Access, reveal this exact Nuke build, or retry access; recovery controls on affected pages link back to Permissions & access and offer folder reselection or Trash-scan retry. Notification authorization and optional SMAppService login registration display observed statuses, unknowns, approval requirements, and failures. No administrator helper or private permission assertion is represented by these controls.

### Docker Availability and Local Metadata

Docker shows engine checking, reachable, or unverified/unavailable status with measured time or an explicit stale last-successful timestamp. Offline cleanup remains unavailable. A separate Local Docker disk section labels read-only VM file metadata as independent of the engine: logical/allocated file observations are not a remote context’s engine usage. Missing metadata means unavailable, elsewhere, or inaccessible rather than zero Docker storage. Copy explains that Nuke never directly removes the VM disk and inspection does not start an engine.

### Find Space and Cached Estimates

Version 0.5 adds an explicit Find space pass over application cache locations and Trash; developer caches live under Developer. It uses the incumbent section titles, native unchecked checkboxes, compact path/explanation rows, a global progress bar, and separate Trash review. A bounded scan limits each location to 12,000 entries or eight seconds; incomplete measurements show a “+” size marker and an amber explanation, keep cleanup selection disabled, and offer Full folder scan or access recovery. A completed pass is saved with the workspace so Cleanup opens on its last evidence; Stop preserves explicitly partial results. Candidate rows expose Reveal, full scan, and running-use inspection; absence of detected uses is not proof of inactivity. Nothing is automatically selected, and the bottom selection total leads to cleanup review. Version 0.8 removes the presentation cap and lazily renders all measured Mac-cache candidates. Trash is measured separately and never inferred empty from denied or partial access.

Storage distinguishes “Measured now” from reused “cached estimate” results with a measurement timestamp. Refresh folder may reuse estimates; Full scan explicitly measures again. The treemap retains its own inspected-item context and Reveal, Scan inside, and Review actions. Saved scan history loads with a visible busy state. Growth root/range/baseline/grouping, resource chart range, status-bar reading, sample interval, and optional alert threshold retain their persisted control values. Growth offers seven days, thirty days, or all scans, with an explicit insufficient-samples state. Adaptive byte units avoid reducing small but real changes to misleading zero-GB labels; exact values remain inspectable.

### Contextual Access Recovery

Access failures retain the blocked inspection’s context. Permissions & access shows a notice naming that inspection, the relevant access controls, and Retry this inspection. Error alerts can route to Review access and retry. This preserves the distinction between asking macOS for access, reporting observed permission status, and retrying an actual operation; it does not claim a global Full Disk Access grant or automatic privilege escalation.

### Alert Inbox and Notification Actions

The Alerts page reuses compact divider-separated rows, secondary timestamps, selectable root paths, quiet Review/Ignore/Unignore/Remind in an hour actions, and visible delivery notes. Empty copy explains optional alerts and the lack of invented historical changes. Notifications offer the same review, ignore, and reminder choices. Review routes to saved Growth when available, a real folder scan otherwise, Processes for CPU, or Find space for storage. Reminders identify the original measurement instead of implying a new observation. Ignored keys and snooze state persist; up to 100 local alert records are retained. Growth alerts use existing complete scans or the active watchlist, with thresholds of 1 GB or at least 100 MB and 20%; alerts do not start background folder scans or perform cleanup. Permission-dependent delivery and scheduling failures remain visible.

### Cleanup Completion Sheet

`ReceiptFinishView` adds an immediate native Cleanup result sheet with a 23-point semibold title, receipt title, explicit succeeded/failed counts, and a scrollable item-outcome list capped at 250 points. The sheet is 620 points wide with 28-point padding and existing 18-point spacing; it uses rust for failure text, selectable original paths, Show in Trash where available, and receipt-specific recovery instructions. Observed-space copy explicitly notes other activity, APFS sharing, and that moving to Trash does not itself reclaim space. View receipt history is quiet; Done uses the existing ink primary style and default keyboard action. The validation capture uses clearly labelled sample outcomes and proves presentation only, not cleanup execution.

### Local Models and Inventory Work

The AI storage page is labelled Local models. It uses the shared inventory list for known Ollama, Hugging Face, and LM Studio roots plus explicitly added folders. Add folder, Inspect models, and Stop retain existing native controls; completion time belongs to the shared inventory summary. Custom locations are inventory-only; removing one from the list does not delete its files. Bounded Ollama/Hugging Face metadata appears in a disclosure group capped at 100 entries, with owner-tool deletion guidance and no separate shared-blob selections. Missing models, unknown active use/download cost, and incomplete location coverage remain explicit. Custom locations have a separate disclosure with selectable paths. Missing custom roots produce a recovery note rather than an empty or zero-size inference.

Filesystem inventories expose Stop while queued or traversing. Copy explains cancellation boundaries, including waiting for a current bounded CLI call where applicable. The persistent DiskActivity strip names the running disk task, elapsed time, waiting count, visited entries and current path, with Stop scan when cancellable. User inspections precede queued watch refreshes. This priority applies to pending work rather than claiming an already running task is preempted. Fresh cleanup-review preparation displays queued-work text and Cancel review before any files move. Live system samples are acquired asynchronously, separate from filesystem inventory presentation.

### Visible Storage Freshness

Version 0.7 adds a secondary 10-point Storage status line stating either automatic folder-change updates or visible periodic refresh when filesystem events are unavailable. It uses existing typography and colors. `FolderFreshness` watches the visible folder, coalesces events to a fixed pending deadline, and allows at most one refresh start per five seconds. More events do not continually push that deadline back. Hidden-window and sleep states suspend this work; the 60-second fallback is used only when events are unavailable. These are bounded visible-folder updates, not a claim that every file everywhere changes instantly.

The storage meter follows current live volume readings. When monitoring is disabled or paused, a visible meter performs a volume-only refresh every ten seconds; it does not trigger folder traversal. Unknown volume capacity is explicitly unavailable in the text and accessibility label rather than a fabricated zero-capacity measurement.

Central cleanup-receipt handling invalidates stale inventories and refreshes relevant measurements after mutation. Previously inspected snapshot tools are marked dirty and refreshed when revisited or the window reopens, rather than silently presenting pre-cleanup data as current. Historical Growth scans retain their saved meaning; automatic folder updates do not rewrite earlier observations. The existing measured/cached-estimate distinctions, timestamps, review safeguards, and partial-access warnings remain authoritative. These changes do not force WidgetKit refresh timing or imply automatic cleanup.

### Cleanup Receipts

History is table-first. A summary strip reports receipt count, successful outcomes, failures, and the latest observed delta. A native selectable receipts table shows date, cleanup title, item count, result, and observed delta; selecting a receipt reveals a second table of original path, size, outcome, and a Show action for its Trash path, plus Export JSON and recovery guidance. Earlier process/Docker activity follows in its own date/action/detail table. Failures use the error red. Recovery instructions describe Finder Put Back where available or manually returning an item to its original location. Export uses a native save panel and a user-selected destination. Receipts are retained locally up to 200; neither receipt guidance nor an observed disk delta is an automatic undo or guaranteed reclaimed-space claim.

### Trash

Trash is a Cleanup tab beside Quick scan and Developer. It inherits existing list, surface, spacing, and typography tokens. Review distinguishes reversible Move to Trash from permanent deletion. The final destructive button uses native semantic red, remains disabled until the exact text EMPTY is entered, and is paired with an explicit cannot-undo explanation. Empty, scanning, permission-error, and populated states are explicit. Scope is current-user home-volume Trash only.


## Do's and Don'ts

### Do:

- Do use the native SF system font and SF Symbols.
- Do align numeric measurements and use monospaced digits where implemented.
- Do keep long content scrollable while progress, Stop, and Files review actions remain visible.
- Do make partial measurements, warnings, and review actions legible.

### Don't:

- Don't substitute web typography or browser controls for the native macOS implementation.
- Don't add shadows or ornamental gradients to the existing flat surfaces.
- Don't treat the supplied screenshot references as assets to ship.

<!-- Version 0.8 evidence: current ContentView, FindSpaceView, FolderTreeView, DeveloperScope, DeveloperScopesView, ManagementViews, MenuMonitorView, WidgetsView, StatusBarController and Widgets/NukeWidgets source. The 3 November refinement removes the global footer and breadcrumb, collapses duplicated scan Stops into the activity bar, adds the resumable Cleanup start surface, caps prose measure, disables Apps alternation, and moves row actions into a labeled menu; .impeccable/review/v09 captures the compact Cleanup start and Developer outcome; .impeccable/review/v10 captures the table-first History. The same refinement adds evidence badges, dry-run plan export, git check-ignore evidence, open-handle warnings, more built-in caches, and a remove-watch action. .impeccable/review/v08 contains compact and wide captures, with native recaptures verifying compact Developer rows and explicit stopped outcomes. apps-compact.png and apps-unfocused-compact.png establish the ink/pale-rust inspection-button treatment in active and inactive states. Popover dismissal is source-verified and manually observed for inside Refresh, Nuke File-menu click-through, Finder File-menu click, and Escape in the final normal signed app. docs/performance/V08.md retains unresolved intermittent-freeze limits; these layout/status changes do not certify all hangs fixed. No new OS permission, login, notification, widget-gallery or destructive-execution claim. -->


## Nuke Sweep identity (4 November 2026)

The approved identity uses a softened N with a single sweeping negative-space cut. Flat charcoal `#262B2B`, burnt orange `#C24521`, and warm ivory `#FBFAF7` match the application palette. `branding/nuke-sweep` holds PNG, SVG, ICNS and iconset masters. `SweepMark` shares the geometry between the sidebar, monitor panel and widgets; the menu bar uses a monochrome template for system contrast. The sidebar wordmark fits the existing 202-point rail. Display name and distribution bundle are Nuke Sweep; bundle identifiers, widget kinds, preference keys and Application Support/Nuke stay stable for upgrade continuity.
