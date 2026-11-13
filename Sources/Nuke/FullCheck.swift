import SwiftUI
import UserNotifications

/// One pass over everything the app knows how to measure.
///
/// The app used to make a person visit Cleanup, Developer and Projects in turn
/// and add the answers up themselves; the summary literally read "1 of 5 areas
/// measured". This runs the same three bounded scans together and ends on one
/// answer: how much can go to review, how much of that comes back by itself, and
/// what was deliberately left out.
///
/// It measures and ranks. It selects nothing and cleans nothing; taking the
/// result to review is a separate, explicit step.
struct FullCheckState: Equatable {
    var running = false
    var started: Date?
    var finished: Date?
    /// Where project build output was looked for, when a code folder was found.
    var projectsRoot: URL?
    /// True when no conventional code folder exists, so projects were not scanned.
    var projectsSkipped = false
    var stopped = false
    /// Started by the weekly schedule rather than by the person.
    var automatic = false
    /// The check before this one, kept so the result can say what changed.
    var previous: FullCheckRecord?
    /// Set when low storage started this check; the free space at that moment.
    var lowStorageFree: Int64?
    /// The locations that grew most since the previous check.
    var growers: [FullCheckGrower] = []
    /// What the automatic cleanup moved, when it is switched on and found work.
    var autoCleaned: AutoCleanOutcome?
    /// Locations macOS would not let the check read completely.
    var gaps = 0
}

/// What one completed check found, kept so the next can be compared with it.
struct FullCheckRecord: Codable, Equatable, Sendable {
    let date: Date
    let regenerableBytes: Int64
    let candidateBytes: Int64
    /// Size per measured location, largest first and bounded, so the next check
    /// can name what grew rather than only say that something did. Optional so
    /// records saved before this existed still decode.
    var sizes: [String: Int64]? = nil
    /// Whether project build output was part of this check. Comparing a check
    /// that measured projects with one that did not would report every project
    /// folder as new.
    var measuredProjects: Bool? = nil
    /// Which places the check looked in, as a version number. A check that
    /// looks in more places finds more without anything having grown, so two
    /// records are only compared when this matches.
    var coverage: Int? = nil
}

/// One location that takes more space than it did at the previous check.
struct FullCheckGrower: Equatable, Sendable, Identifiable {
    let path: String
    let delta: Int64
    /// Not present in the previous record at all.
    let isNew: Bool
    var id: String { path }
    /// Enough of the path to recognise: a bare "Caches" or "node_modules" says
    /// nothing, so the parent folder travels with it.
    var name: String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty || parent == "/" ? url.lastPathComponent : parent + "/" + url.lastPathComponent
    }
}

/// The reason to come back. One cleanup is a one-time use; what brings someone
/// back is being told, without asking, that the clearable space has built up
/// again. Opt-in, measures only, and runs while the app or its menu-bar item is
/// open — it never cleans and never wakes the Mac.
enum FullCheckHistory {
    private static let recordKey = "nuke.fullCheck.last"
    private static let weeklyKey = "nuke.fullCheck.weekly"
    static let interval: TimeInterval = 7 * 86_400
    /// Growth below this is noise: caches breathe by hundreds of megabytes a day.
    static let notableGrowth: Int64 = 1_000_000_000

    static var last: FullCheckRecord? {
        get { UserDefaults.standard.data(forKey: recordKey).flatMap { try? JSONDecoder().decode(FullCheckRecord.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: recordKey) }
            else { UserDefaults.standard.removeObject(forKey: recordKey) }
        }
    }
    static var weeklyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: weeklyKey) }
        set { UserDefaults.standard.set(newValue, forKey: weeklyKey) }
    }

    static func isDue(last: FullCheckRecord?, now: Date = Date(), enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last.date) >= interval
    }

    /// What changed since the previous check, or nil when there is nothing to say.
    /// Raised whenever the check starts measuring somewhere new. 2 added build
    /// folders in projects outside the chosen code folder.
    static let coverage = 2

    static func change(previous: FullCheckRecord?, current: FullCheckRecord) -> String? {
        guard let previous, previous.coverage == current.coverage else { return nil }
        let delta = current.regenerableBytes - previous.regenerableBytes
        let when = previous.date.formatted(date: .abbreviated, time: .omitted)
        if delta >= notableGrowth { return String(format: String(localized: "%@ more than on %@."), bytes(delta), when) }
        if delta <= -notableGrowth { return String(format: String(localized: "%@ less than on %@."), bytes(-delta), when) }
        return String(format: String(localized: "About the same as on %@."), when)
    }

    /// A weekly check only interrupts when the answer has materially grown.
    static func shouldNotify(previous: FullCheckRecord?, current: FullCheckRecord) -> Bool {
        guard let previous, previous.coverage == current.coverage else { return current.regenerableBytes >= notableGrowth }
        return current.regenerableBytes - previous.regenerableBytes >= notableGrowth
    }
}

extension AppModel {
    static let fullCheckRootName = "This Mac"

    /// True while the panel's numbers describe the whole-Mac pass rather than a
    /// later single-folder scan that has since replaced the ranking.
    var fullCheckResultIsCurrent: Bool {
        fullCheck.finished != nil && !fullCheck.running && triage.rootName == Self.fullCheckRootName
    }

    @discardableResult
    func startFullCheck(automatic: Bool = false, lowStorageFree: Int64? = nil) -> Bool {
        guard !fullCheck.running, !actionBusy, !quick.busy, !cacheScanning, !features.projectLoading, !personal.running else { return false }
        fullCheck = FullCheckState(running: true, started: Date(), automatic: automatic, previous: FullCheckHistory.last, lowStorageFree: lowStorageFree)
        Log.scan.notice("Full check starting: automatic=\(automatic, privacy: .public)")
        quickSelected = []
        findSpace()
        scanCaches()
        Task {
            // Projects need a folder. Reuse the one already chosen, otherwise the
            // conventional location holding the most projects; with neither, the
            // area is reported as not measured rather than silently skipped.
            var root = features.projectRoot
            if root == nil {
                let found = await DiskWork.run("Looking for your code", lane: .interactive) { CodeFolderDetection.detect(deep: true) }
                root = found.first?.url
            }
            guard fullCheck.running else { return }
            if let root {
                fullCheck.projectsRoot = root
                FolderAccess.shared.remember(root)
                features.scanProjects(rootOverride: root)
            } else {
                fullCheck.projectsSkipped = true
            }
            // Personal files are searched after the code folder is known, so
            // that folder is left to the project scan and not walked twice.
            scanPersonalFiles()
            // Each scan publishes its own busy flag; wait for all three to clear.
            while fullCheck.running, quick.busy || cacheScanning || features.projectLoading || personal.running {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard fullCheck.running else { return }
            let items = fullCheckItems()
            triage.refresh(items: items, rootName: Self.fullCheckRootName, signals: triageSignals())
            // Ranking is part of the check: the result is only an answer once the
            // totals exist, so the run stays "running" until they do.
            while fullCheck.running, triage.computing { try? await Task.sleep(for: .milliseconds(150)) }
            guard fullCheck.running else { return }
            fullCheck.running = false
            fullCheck.finished = Date()
            Log.scan.notice("Full check finished: items=\(items.count, privacy: .public) projectsSkipped=\(self.fullCheck.projectsSkipped, privacy: .public)")
            fullCheck.gaps = fullCheckGaps()
            guard let report = triage.report else { postPlainLowStorageAlertIfNeeded(); return }
            let totals = report.totals
            let measuredProjects = !fullCheck.projectsSkipped
            let record = FullCheckRecord(
                date: Date(), regenerableBytes: totals.regenerableBytes, candidateBytes: totals.candidateBytes,
                sizes: FullCheckHistory.sizes(of: items), measuredProjects: measuredProjects, coverage: FullCheckHistory.coverage
            )
            let previous = fullCheck.previous
            fullCheck.growers = FullCheckHistory.growers(
                previous: previous?.sizes, current: items,
                // Only call something new when both checks looked in the same places.
                includeNew: previous?.measuredProjects == measuredProjects && previous?.coverage == record.coverage
            )
            let grew = FullCheckHistory.growthSentence(fullCheck.growers, since: previous?.date)
            // The automatic cleanup acts first, so the alert describes what is
            // left for the person rather than what has already been handled.
            fullCheck.autoCleaned = await runAutoClean(report)
            let cleaned = fullCheck.autoCleaned?.movedBytes ?? 0
            let remaining = max(0, record.regenerableBytes - cleaned)
            if let free = fullCheck.lowStorageFree {
                // Low storage is when someone needs the answer, so this alert is
                // sent whatever the weekly comparison says.
                var detail = String(format: String(localized: "%@ available."), bytes(free))
                if let grew { detail += " " + grew }
                if remaining > 0 {
                    detail += " " + String(format: String(localized: "%@ comes back by itself; review it to clear it."), bytes(remaining))
                } else {
                    detail += " " + String(localized: "Nothing that rebuilds itself is left to clear; open Nuke Sweep to see what is taking the space.")
                }
                AlertCenter.shared.post(key: "storage", title: String(localized: "Storage is running low"), detail: detail, enabled: true)
            } else if fullCheck.automatic, remaining >= FullCheckHistory.notableGrowth, FullCheckHistory.shouldNotify(previous: previous, current: record) {
                let change = FullCheckHistory.change(previous: previous, current: record) ?? ""
                AlertCenter.shared.post(
                    key: "fullcheck",
                    title: String(format: String(localized: "%@ can be cleared"), bytes(remaining)),
                    detail: [change, grew ?? "", String(localized: "It comes back by itself. Review it when you are ready.")].filter { !$0.isEmpty }.joined(separator: " "),
                    enabled: true
                )
            }
            FullCheckHistory.last = record
        }
        return true
    }

    /// The low-storage alert must not be lost because a check could not finish.
    private func postPlainLowStorageAlertIfNeeded() {
        guard let free = fullCheck.lowStorageFree else { return }
        AlertCenter.shared.post(
            key: "storage", title: String(localized: "Storage is running low"),
            detail: String(format: String(localized: "%@ available."), bytes(free)) + " " + String(localized: "Open Nuke Sweep to check what can be cleared."),
            enabled: true
        )
    }

    /// Offered the low-storage moment by the monitor. Returns true when a check
    /// was started and will post the alert itself, with what grew and what can go.
    func handleLowStorage(free: Int64) -> Bool {
        // Never during a demo, a capture or a latency run: a whole-Mac check
        // starting by itself would distort exactly what those are measuring.
        let arguments = ProcessInfo.processInfo.arguments
        guard !["--demo-fixtures", "--capture", "--measure-ui", "--bench-scan"].contains(where: arguments.contains) else { return false }
        // A check resets the quick-scan selection. Never do that under someone
        // who is in the middle of choosing or reviewing.
        guard quickSelected.isEmpty, !showTrashReview, pendingTrash.isEmpty, !reviewPreparing else { return false }
        return startFullCheck(automatic: true, lowStorageFree: free)
    }

    /// How many measured locations came back partial because of access.
    func fullCheckGaps() -> Int {
        caches.filter { $0.skipped > 0 }.count + (quick.trashPartial ? 1 : 0) + quick.entries.filter { $0.item.incomplete }.count
    }

    /// Re-reads whether Full Disk Access appears granted. Cheap, but it touches
    /// the filesystem, so it stays off the main actor.
    func refreshDiskAccess() {
        Task {
            let status = await Task.detached(priority: .utility) { DiskAccessProbe.status() }.value
            if diskAccess != status { diskAccess = status }
        }
    }

    /// Runs the weekly check when it is due. Called at launch and on a slow
    /// timer; does nothing unless the person switched the weekly check on.
    func runWeeklyCheckIfDue() {
        guard FullCheckHistory.isDue(last: FullCheckHistory.last, enabled: FullCheckHistory.weeklyEnabled) else { return }
        guard !ProcessInfo.processInfo.arguments.contains("--demo-fixtures") else { return }
        startFullCheck(automatic: true)
    }

    func setWeeklyCheck(_ enabled: Bool) {
        FullCheckHistory.weeklyEnabled = enabled
        fullCheckWeekly = enabled
        // The automatic cleanup is offered as part of the weekly check. Leaving
        // it armed after its controls disappear would let a low-storage check
        // clean on the strength of a switch the person can no longer see.
        if !enabled, autoCleanEnabled { setAutoClean(false) }
        // The weekly check is only useful if it can say something, so ask for
        // notification permission at the moment the person opts in.
        if enabled { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
    }

    func stopFullCheck() {
        guard fullCheck.running else { return }
        let lowStorage = fullCheck.lowStorageFree != nil
        fullCheck.running = false
        fullCheck.stopped = true
        if lowStorage { postPlainLowStorageAlertIfNeeded() }
        stopFindSpace(); cancelCaches(); features.cancelProjects(); personalToken.cancel()
    }

    /// Everything the three scans measured, merged for one ranking.
    func fullCheckItems() -> [DiskItem] {
        FullCheckHistory.merge(caches.compactMap(\.item) + features.projects.flatMap(\.entries).map(\.item) + (personal.report?.strayBuilds ?? []) + quick.entries.map(\.item))
    }
}

extension FullCheckHistory {
    /// How many locations a record remembers. Enough that anything large is in
    /// it; small enough to sit in preferences.
    static let storedSizes = 200
    /// Growth in one location below this is not worth naming.
    static let notableLocationGrowth: Int64 = 250_000_000

    static func sizes(of items: [DiskItem]) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for item in items.sorted(by: { $0.size > $1.size }).prefix(storedSizes) {
            sizes[item.url.standardizedFileURL.path] = item.size
        }
        return sizes
    }

    /// The locations that grew most since the previous record, largest first.
    static func growers(previous: [String: Int64]?, current: [DiskItem], includeNew: Bool = true, limit: Int = 3) -> [FullCheckGrower] {
        guard let previous, !previous.isEmpty else { return [] }
        // A location missing from a full record was not necessarily absent: it
        // may simply have been smaller than everything that was kept. Its growth
        // is then at least its size above that cut-off, and no more is claimed.
        let floor = previous.count >= storedSizes ? (previous.values.min() ?? 0) : 0
        var found: [FullCheckGrower] = []
        for item in current {
            let path = item.url.standardizedFileURL.path
            if let before = previous[path] {
                let delta = item.size - before
                if delta >= notableLocationGrowth { found.append(.init(path: path, delta: delta, isNew: false)) }
            } else if includeNew {
                let delta = item.size - floor
                if delta >= notableLocationGrowth { found.append(.init(path: path, delta: delta, isNew: floor == 0)) }
            }
        }
        found.sort { $0.delta == $1.delta ? $0.path < $1.path : $0.delta > $1.delta }
        return Array(found.prefix(max(0, limit)))
    }

    /// "Since 3 Nov: Xcode/DerivedData +8.2 GB, web/node_modules new at 5 GB."
    static func growthSentence(_ growers: [FullCheckGrower], since: Date?) -> String? {
        guard !growers.isEmpty, let since else { return nil }
        let parts = growers.map { grower in
            grower.isNew
                ? String(format: String(localized: "%@ new at %@"), grower.name, bytes(grower.delta))
                : String(format: String(localized: "%@ +%@"), grower.name, bytes(grower.delta))
        }
        return String(format: String(localized: "Since %@: %@."), since.formatted(date: .abbreviated, time: .omitted), parts.joined(separator: ", "))
    }

    /// De-duplicates by path and drops anything nested inside another measured
    /// item. A location can appear in more than one scan (a cache rule that lives
    /// under ~/Library/Caches), and counting it twice would inflate the headline.
    /// Earlier entries win, so callers list the more specific scans first.
    static func merge(_ all: [DiskItem]) -> [DiskItem] {
        var seen = Set<String>(), items: [DiskItem] = []
        for item in all where item.size > 0 && seen.insert(item.url.standardizedFileURL.path).inserted {
            items.append(item)
        }
        let paths = items.map { $0.url.standardizedFileURL.path }
        return items.filter { item in
            let path = item.url.standardizedFileURL.path
            return !paths.contains { $0 != path && path.hasPrefix($0 + "/") }
        }
    }
}

/// The first thing on the Cleanup page: one button, then one answer.
struct FullCheckCard: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features

    var body: some View {
        Surface {
            if model.fullCheck.running {
                running
            } else if model.fullCheckResultIsCurrent, let report = model.triage.report {
                result(report)
            } else if model.fullCheck.finished != nil, model.triage.computing {
                BusyLine(text: "Working out what deserves attention…")
            } else {
                invitation
            }
        }
        .onAppear { model.refreshDiskAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshDiskAccess() }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("See what you can clear, and what it would cost you").font(.system(size: 17, weight: .semibold))
                Text("One pass over caches, project build output, Trash, and your own files: installers, repeat downloads, recordings, old backups. Usually a minute or two.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 9) {
                promise("arrow.uturn.backward.circle", "Nothing is deleted. Reviewed items move to Trash, with a receipt and a way back.")
                promise("exclamationmark.shield", "Anything with no copy anywhere else is held back and named, not offered.")
                if model.autoCleanEnabled {
                    promise("checkmark.shield", "Nothing is selected for you, apart from the automatic cleanup you switched on. Every item is rechecked at the moment it moves.")
                } else {
                    promise("checkmark.shield", "Nothing is selected for you. Every item is rechecked at the moment it moves.")
                }
            }
            if model.diskAccess == .missing { AccessStep() }
            HStack {
                Spacer()
                Button(model.diskAccess == .missing ? "Check without it" : "Check this Mac") { model.startFullCheck() }
                    .buttonStyle(PrimaryButton()).disabled(model.actionBusy || model.quick.busy || model.cacheScanning || features.projectLoading || model.personal.running)
            }
        }
    }

    private func promise(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.green).frame(width: 16)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Checking this Mac…").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Stop") { model.stopFullCheck() }.buttonStyle(QuietButton())
            }
            step("Application caches and Trash", active: model.quick.busy, done: model.quick.measured != nil)
            step("Developer caches", active: model.cacheScanning, done: !model.cacheScanning && !model.caches.isEmpty)
            if model.fullCheck.projectsSkipped {
                step("Project build output — no code folder found", active: false, done: false)
            } else {
                step("Project build output", active: features.projectLoading, done: !features.projectLoading && model.fullCheck.projectsRoot != nil)
            }
            step("Installers, downloads, recordings and backups", active: model.personal.running, done: !model.personal.running && model.personal.report != nil)
            step("Working out what deserves attention", active: model.triage.computing, done: false)
        }
    }

    private func step(_ title: LocalizedStringKey, active: Bool, done: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.dotted" : "circle")
                .font(.system(size: 11)).foregroundStyle(done ? Theme.green : Theme.secondary).frame(width: 16)
            Text(title).font(.system(size: 12)).foregroundStyle(active || done ? Theme.ink : Theme.secondary)
        }
    }

    @ViewBuilder private func result(_ report: StorageTriage.Report) -> some View {
        let totals = report.totals
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(totals.candidateBytes > 0 ? "Here is what you can clear" : (model.personal.report?.totalBytes ?? 0) > 0 ? "Nothing rebuilds itself here, but your own files are worth a look" : "Nothing worth clearing was found")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Check again") { model.startFullCheck() }.buttonStyle(QuietButton())
            }
            if totals.candidateBytes > 0 {
                HStack(alignment: .top, spacing: 26) {
                    figure(bytes(totals.regenerableBytes), "comes back by itself", "Caches, dependencies and build output nothing is using", tint: Theme.green)
                    figure(bytes(totals.candidateBytes), "open to review in total", "\(totals.candidateCount) locations with local evidence", tint: Theme.ink)
                    if totals.exposedCount > 0 {
                        figure(bytes(totals.exposedBytes), "held back", "No copy exists anywhere else", tint: Theme.error)
                    }
                }
                if let previous = model.fullCheck.previous,
                   let change = FullCheckHistory.change(previous: previous, current: .init(date: Date(), regenerableBytes: totals.regenerableBytes, candidateBytes: totals.candidateBytes, coverage: FullCheckHistory.coverage)) {
                    Text(verbatim: change).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                if !model.fullCheck.growers.isEmpty, let previous = model.fullCheck.previous {
                    growth(model.fullCheck.growers, since: previous.date)
                }
                if let cleaned = model.fullCheck.autoCleaned, cleaned.movedCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle").font(.system(size: 11)).foregroundStyle(Theme.green)
                        Text("Automatic cleanup moved \(bytes(cleaned.movedBytes)) to Trash after this check. The figures above were measured before it ran.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("See the receipt") { model.page = .history }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                    }
                }
                if let personal = model.personal.report, personal.totalBytes > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.square").font(.system(size: 11)).foregroundStyle(Theme.orange)
                        Text("Also found: \(bytes(personal.totalBytes)) in \(personal.findings.count) of your own files, listed below. None of it rebuilds itself, so it is not part of these figures.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if totals.inUseCount > 0 {
                    Text("\(totals.inUseCount) of these are in use right now and are left out of the first figure.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if model.fullCheck.projectsSkipped && features.projectRoot == nil {
                    HStack(spacing: 10) {
                        Text("Project build output was not measured: no code folder was found in the usual places.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Choose your code folder…") { features.scanProjects() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                            .help("Measured now, and included every time you check again")
                    }
                } else if model.fullCheck.projectsSkipped {
                    Text("A code folder is now chosen. Check again to include its build output in these figures.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if model.fullCheck.gaps > 0 || model.diskAccess == .missing {
                    if model.diskAccess == .missing {
                        AccessStep(afterCheck: true)
                    } else {
                        Text("\(model.fullCheck.gaps) locations could only be measured in part, so these figures are a lower bound.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
                Toggle("Check weekly and tell me when this has grown", isOn: Binding(
                    get: { model.fullCheckWeekly },
                    set: { model.setWeeklyCheck($0) }
                ))
                .toggleStyle(.checkbox).font(.system(size: 11))
                .help(model.autoCleanEnabled
                      ? "Runs while Nuke Sweep or its menu-bar item is open. Also runs when storage gets low."
                      : "Measures only, while Nuke Sweep or its menu-bar item is open. It never cleans anything.")
                if model.fullCheckWeekly { autoCleanControls(report) }
                HStack(spacing: 10) {
                    Text("Sizes are measured, not promised: space returns when Trash is emptied.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Review what comes back by itself…") { model.reviewTrash(report.regenerable) }
                        .buttonStyle(PrimaryButton()).disabled(report.regenerable.isEmpty || model.actionBusy)
                        .help("Opens the review with these items listed. Nothing moves until you confirm there.")
                }
            }
        }
    }

    private func growth(_ growers: [FullCheckGrower], since: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("What grew since \(since.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: 11, weight: .semibold))
            ForEach(growers) { grower in
                HStack(spacing: 8) {
                    Text(verbatim: (grower.isNew ? "" : "+") + bytes(grower.delta))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.orange)
                        .frame(width: 78, alignment: .trailing)
                    Text(verbatim: grower.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    if grower.isNew { Text("new").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    Spacer(minLength: 0)
                    Button("Show") { model.reveal(URL(fileURLWithPath: grower.path)) }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                        .help(grower.path)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The opt-in for unattended cleanup, with what it would do right now so
    /// the choice is made against real numbers rather than a description.
    @ViewBuilder private func autoCleanControls(_ report: StorageTriage.Report) -> some View {
        let wouldMove = AutoClean.eligible(report, idleDays: model.autoCleanIdleDays)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Toggle("After each weekly check, move to Trash what rebuilds itself and has been untouched for", isOn: Binding(
                    get: { model.autoCleanEnabled },
                    set: { model.setAutoClean($0) }
                ))
                .toggleStyle(.checkbox).font(.system(size: 11))
                Picker("Untouched for", selection: Binding(
                    get: { model.autoCleanIdleDays },
                    set: { model.setAutoCleanIdleDays($0) }
                )) {
                    ForEach(AutoClean.idleChoices, id: \.self) { days in Text("\(days) days").tag(days) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            }
            Group {
                if wouldMove.isEmpty {
                    Text("Right now that would move nothing: everything that rebuilds itself has been used more recently.")
                } else {
                    Text("Right now that would move \(bytes(wouldMove.reduce(0) { $0 + $1.size })) in \(wouldMove.count) locations. Only caches, dependencies and build output with nothing to warn about; each run leaves a receipt that can put them back, and Trash is never emptied for you.")
                }
            }
            .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
        }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey, _ detail: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
            Text(label).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a scheduled folder scan found that is worth saying.
///
/// "Finished: 41 GB" is a status. "Grew 12 GB since 3 Nov, 9 GB of it
/// regenerates" is a reason to open the app. Growth is judged per item against
/// the previous saved scan of the same folder, and only growth in items local
/// evidence says regenerate counts towards the second figure.
enum GrowthDigest {
    /// Below this the folder has not meaningfully changed.
    static let notable: Int64 = 500_000_000

    static func sentence(
        previous: StoredScan?,
        current: ScanResult,
        classify: (DiskItem) -> CleanupEvidence = { CleanupEvidenceService.classify($0.url) }
    ) -> String? {
        guard let previous else { return nil }
        let delta = current.logical - previous.total
        guard delta >= notable else { return nil }
        var regenerable: Int64 = 0
        for item in current.items {
            let growth = item.size - (previous.sizes[item.name] ?? 0)
            // Classifying touches the filesystem, so only items that grew enough
            // to matter are looked at.
            guard growth >= 10_000_000 else { continue }
            if classify(item).kind.supportsContentsReview { regenerable += growth }
        }
        let since = previous.date.formatted(date: .abbreviated, time: .omitted)
        let head = String(format: String(localized: "Grew %@ since %@."), bytes(delta), since)
        guard regenerable >= notable / 5 else { return head }
        return head + " " + String(format: String(localized: "%@ of that regenerates by itself."), bytes(min(regenerable, delta)))
    }
}
