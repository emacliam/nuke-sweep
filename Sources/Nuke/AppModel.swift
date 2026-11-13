import SwiftUI
import AppKit
import UserNotifications

@Observable @MainActor final class AppModel {
    let features = FeatureModel()
    var mainWindowVisible = true { didSet { if oldValue != mainWindowVisible { reconcileLiveFolder(); if mainWindowVisible { refreshDirtyVisibleInventory() } } } }
    var storageIsLive = false
    private let folderFreshness = FolderFreshness()
    private var storageUpdatesStarted = false
    private var resourceRefreshID = UUID()
    private var sleeping = false
    private var storageDirty = false
    private var pendingMutationRefresh = false
    var openMainWindow: (() -> Void)?
    var statusController: StatusBarController?
    private var servicesStarted = false
    private var filters: [String: String] = [:]
    private var persistSessionEnabled = true
    private var sessionSave: DispatchWorkItem?
    var focusedStorageItem: String? { didSet { scheduleSessionSave() } }
    var resultMeasured: Date?
    var scanState = "Not scanned"
    var recovery: RecoveryTask?
    var reviewPreparing = false
    var cleanupBasket = CleanupBasket()
    var showCleanupBasket = false
    var basketReviewRequested = false
    func addToBasket(_ items: [DiskItem], proofs: [DuplicateProof] = []) {
        do { try cleanupBasket.add(items, proofs: proofs); showCleanupBasket = true }
        catch { message = error.localizedDescription }
    }
    func reviewBasketIfRequested() {
        guard basketReviewRequested else { return }; basketReviewRequested = false
        reviewTrash(cleanupBasket.items, proofs: cleanupBasket.proofs)
    }
    private var reviewToken = ScanCancellation()
    private var dockerStartTask: Task<Void, Never>?
    var finishedReceipt: CleanupReceipt?
    var quick = QuickScanState()
    let ai = AISettings()
    /// Owns the ranked "what matters here" shortlist. Separate from AppModel so
    /// ranking and AI state invalidate only the panel that shows them.
    let triage = TriageStore()
    /// The one-button "check this Mac" pass. See `FullCheck.swift`.
    var fullCheck = FullCheckState()
    var personal = PersonalFilesState()
    @ObservationIgnored var personalToken = ScanCancellation()
    /// Mirrors the stored preference so the toggle redraws when it changes.
    var fullCheckWeekly = FullCheckHistory.weeklyEnabled
    /// Mirror the automatic-cleanup preferences for the same reason.
    var autoCleanEnabled = AutoClean.enabled
    var autoCleanIdleDays = AutoClean.idleDays
    /// Whether Full Disk Access appears granted. See `DiskAccessProbe`.
    var diskAccess = DiskAccessProbe.Status.unknown
    private var weeklyCheckTimer: Timer?
    /// Local context that sharpens the ranking when it happens to be available.
    /// Every part is optional: triage degrades to size-and-evidence without it,
    /// and nothing here triggers work of its own.
    func triageSignals() -> StorageTriage.Signals {
        var signals = StorageTriage.Signals()
        // Project ids are their root paths; a mapped port or dev process means
        // something is using that workspace right now.
        signals.activeRoots = Set(projectPortActivity.filter { !$0.value.isEmpty }.keys)
        signals.duplicateExtraBytes = duplicateProofs.reduce(into: [:]) { totals, proof in
            totals[proof.duplicate.id, default: 0] += proof.duplicate.size
        }
        signals.uncommittedRoots = uncommittedProjectRoots
        signals.openPaths = openFilePaths
        signals.manualOnlyRoots = Set(personal.report?.strayProjectRoots ?? [])
        return signals
    }

    /// Paths a running process currently holds open, from the same bounded lsof
    /// snapshot review already uses. Cached rather than probed per ranking: one
    /// snapshot answers for every item.
    private(set) var openFilePaths: Set<String> = []

    /// Takes one lsof snapshot off the main actor. Safe to call repeatedly.
    func refreshOpenFiles() {
        Task {
            let paths = await DiskWork.run("Checking open files", lane: .interactive) {
                Set(FileUseService.snapshot().map(\.path))
            }
            openFilePaths = paths
            Log.scan.info("Open-file snapshot: paths=\(paths.count, privacy: .public)")
        }
    }

    /// What has been measured across every area, and what has not been looked at.
    /// Deliberately not a single reclaimable total: see `ReclaimSummary`.
    var reclaimSummary: ReclaimSummary {
        ReclaimSummary.make(
            quickBytes: quick.entries.reduce(0) { $0 + $1.item.size },
            quickMeasured: quick.measured != nil,
            developerBytes: caches.compactMap(\.item).reduce(0) { $0 + $1.size },
            developerMeasured: !caches.isEmpty,
            projectBytes: features.projects.reduce(0) { $0 + $1.size },
            projectsMeasured: features.projectRoot != nil,
            trashBytes: quick.trashSize,
            duplicateBytes: features.duplicates?.groups.reduce(0) { $0 + $1.extraBytes } ?? 0,
            duplicatesMeasured: features.duplicates != nil
        )
    }

    /// Project roots whose repository has uncommitted work. Refreshed by
    /// `refreshRepositoryState()` rather than probed inline: each check shells out
    /// to git, and triage must not start a process per item.
    private(set) var uncommittedProjectRoots: Set<String> = []

    /// Probes the discovered project roots once, off the main actor. Safe to call
    /// repeatedly; it replaces the previous answer wholesale.
    func refreshRepositoryState() {
        let roots = features.projects.map(\.root)
        guard !roots.isEmpty else { uncommittedProjectRoots = []; return }
        Task {
            let dirty = await DiskWork.run("Checking repository state", lane: .interactive) {
                Set(roots.filter { GitInspection.hasUncommittedChanges(near: $0) == true }.map(\.path))
            }
            uncommittedProjectRoots = dirty
            Log.scan.info("Repository state: dirty=\(dirty.count, privacy: .public) of \(roots.count, privacy: .public)")
        }
    }
    let scheduledScans = ScheduledScanStore()
    /// Last completed pass, kept while a new pass runs so quitting mid-scan cannot erase evidence.
    private var completedQuick: QuickScanState?
    var quickSelected = Set<String>()
    var quickSelectedItems: [DiskItem] { quick.entries.filter { quickSelected.contains($0.id) && !$0.item.incomplete }.map(\.item) }
    private let scanner = IncrementalScanner()
    private var quickToken = ScanCancellation()
    func isCurrentQuick(_ token: ScanCancellation) -> Bool { quickToken === token }
    func quickTokenForScan() -> ScanCancellation { quickToken }
    func newQuickToken() -> ScanCancellation { quickToken = ScanCancellation(); return quickToken }
    func stopFindSpace() { quickToken.cancel() }
    private var duplicateProofs: [DuplicateProof] = []
    var page: Page = .findSpace {
        didSet { if oldValue != page { filters[oldValue.rawValue] = search; search = filters[page.rawValue] ?? ""; scheduleSessionSave(); reconcileLiveFolder(); refreshDirtyVisibleInventory() } }
    }
    var resources = ResourceSnapshot()
    var result: ScanResult?
    var scanRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads") { didSet { scheduleSessionSave(); reconcileLiveFolder() } }
    var scanning = false
    var cacheScanning = false
    var cacheOutcome = "Not scanned"
    var caches: [CacheMeasurement] = []
    var processes: [ProcessRow] = []
    var processLoading = false
    var processError: String?
    var listeningPorts: [ListeningPort] = []
    var portsLoading = false
    var portsError: String?
    var portsUpdated: Date?
    var projectPortActivity: [String: [String]] = [:]
    var projectActivityLoading = false
    var docker: [DockerUsage] = []
    var dockerContext = ""
    var dockerLoading = false
    var dockerError: String?
    var dockerUpdated: Date?
    var dockerReachable = false
    var dockerStarting = false
    var dockerDisks: [DiskItem] = []
    var dockerVolumes: [DockerVolume] = []
    var dockerVolumeError: String?
    var selected = Set<String>()
    /// Bumped for manual scans so the Files tree can drop stale expansions without collapsing on periodic refresh.
    var treeResetToken = UUID()
    var search = "" { didSet { filters[page.rawValue] = search; scheduleSessionSave() } }
    /// Incremented by the ⌘F command so whichever filter is on screen can take focus.
    var focusFilterRequest = 0
    var pendingTrash: [DiskItem] = []
    var pendingTrashSelection = Set<String>()
    var selectedPendingTrash: [DiskItem] { pendingTrash.filter { pendingTrashSelection.contains($0.id) } }
    var pendingEvidence: [String: CleanupEvidence] = [:]
    var pendingWarnings: [String] = []
    var pendingBlocked: [ReviewBlockedItem] = []
    var showTrashReview = false
    var quitWhenIdle = false
    var actionBusy = false {
        didSet { if !actionBusy && quitWhenIdle { FilePersistence.flush(); NSApp.reply(toApplicationShouldTerminate: true) }; if !actionBusy && pendingMutationRefresh && !quitWhenIdle { pendingMutationRefresh = false; refreshAfterMutation() } }
    }
    var message: String?
    var activities: [Activity] = []
    var trashSnapshot: TrashSnapshot?
    var trashLoading = false
    var trashError: String?
    var trashSelected = Set<String>()
    var trashUpdated: Date?
    private var scanToken = ScanCancellation()
    private var cacheToken = ScanCancellation()
    private var cacheGeneration = UUID()
    private var scanGeneration = UUID()
    var visibleItems: [DiskItem] { (result?.items ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var selectedItems: [DiskItem] { (result?.items ?? []).filter { selected.contains($0.id) } }
    var cacheBytes: Int64 { caches.reduce(0) { $0 + ($1.item?.size ?? 0) } }
    init(restoring: Bool = true) {
        let shouldRestore = restoring && !ProcessInfo.processInfo.arguments.contains("--capture-fresh")
        scheduledScans.onScan = { [weak self] url, result in
            guard let self else { return nil }
            // Compared before saving, while the previous scan is still the newest.
            let digest = GrowthDigest.sentence(previous: self.features.scans.first { $0.root == url.path }, current: result)
            self.features.saveScan(root: url, result: result)
            // Close the loop: a scheduled scan that only files a measurement
            // leaves the work of reading it to the user. Ranking it here means
            // the notification leads somewhere already answered. Still never
            // selects or cleans anything -- triage only describes.
            guard !result.items.isEmpty else { return digest }
            self.triage.refresh(items: result.items, rootName: url.lastPathComponent, signals: self.triageSignals())
            Log.scan.info("Scheduled scan ranked: items=\(result.items.count, privacy: .public)")
            return digest
        }
        persistSessionEnabled = shouldRestore && !ProcessInfo.processInfo.arguments.contains("--demo-fixtures")
        if let data = UserDefaults.standard.data(forKey: "nuke.history"), let stored = try? JSONDecoder().decode([Activity].self, from: data) { activities = stored }
        if shouldRestore { refreshResources() }
        if shouldRestore, let data = UserDefaults.standard.data(forKey: "nuke.dockerUsage"), let saved = try? JSONDecoder().decode(DockerSavedUsage.self, from: data) { docker = saved.rows; dockerContext = saved.context; dockerUpdated = saved.date; dockerVolumes = saved.volumes ?? []; dockerError = "Saved Docker measurement — refresh to check the engine." }
        if ProcessInfo.processInfo.arguments.contains("--demo-fixtures") { DemoFixtures.apply(to: self) }
        if ProcessInfo.processInfo.arguments.contains("--demo-ai") { ai.applyDemoConfiguration() }
        features.onReceipt = { [weak self] receipt in
            guard let self else { return }; self.finishedReceipt = receipt
            self.pendingMutationRefresh = true
            if !self.actionBusy { self.pendingMutationRefresh = false; self.refreshAfterMutation() }
        }
        if shouldRestore, let data = UserDefaults.standard.data(forKey: "nuke.workspace"), let saved = try? JSONDecoder().decode(WorkspaceState.self, from: data) {
            filters = saved.filters; page = saved.page == "AI storage" ? .ai : (saved.page == "Overview" ? .findSpace : (Page(rawValue: saved.page) ?? .findSpace)); scanRoot = saved.root
            search = saved.filters[page.rawValue] ?? ""; focusedStorageItem = saved.focusedItem
            result = saved.snapshot; resultMeasured = saved.measured
            if result != nil { scanState = "Saved measurement — refresh before review" }
            if let saved = saved.quick {
                quick = saved; quick.busy = false; completedQuick = saved
                if quick.measured == nil { quick.step = "Interrupted — the last pass did not finish" }
                quickSelected = []
            }
            // A restored measurement is still a measurement: rank it so the panel
            // is populated on launch rather than only after a fresh scan. The
            // saved sizes are stale, which the page already states.
            if let restored = result, !restored.items.isEmpty {
                triage.refresh(items: restored.items, rootName: scanRoot.lastPathComponent, signals: triageSignals())
            } else if let entries = saved.quick?.entries, !entries.isEmpty {
                triage.refresh(items: entries.map(\.item), rootName: "Cleanup", signals: triageSignals())
            }
        }
    }
    func scheduleSessionSave() {
        guard persistSessionEnabled else { return }
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSession() }; sessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    func saveSession() {
        guard persistSessionEnabled else { return }
        let snapshot = result.flatMap { $0.items.count <= 1500 ? $0 : nil }
        // Only a completed pass is evidence; keep the previous one while a new pass is running.
        if quick.measured != nil { completedQuick = quick }
        let state = WorkspaceState(page: page.rawValue, root: scanRoot, filters: filters, focusedItem: focusedStorageItem, snapshot: snapshot, measured: resultMeasured, quick: completedQuick)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "nuke.workspace") }
    }
    func startServices() {
        guard !servicesStarted else { return }; servicesStarted = true
        if !ProcessInfo.processInfo.arguments.contains("--without-status-item") { statusController = StatusBarController(model: self) }; features.monitor.configureMonitor()
        AppDelegate.shared?.model = self
        AlertCenter.shared.model = self
        // Started here rather than in applicationDidFinishLaunching: the delegate's
        // model reference is only assigned above, once the first view appears.
        LatencyBench.startIfRequested(model: self)
        // The weekly check: once shortly after launch, then on a slow timer so a
        // menu-bar session that stays open for days still gets its turn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.runWeeklyCheckIfDue() }
        weeklyCheckTimer = Timer.scheduledTimer(withTimeInterval: 3 * 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runWeeklyCheckIfDue() }
        }
        weeklyCheckTimer?.tolerance = 600
        features.monitor.onLowStorage = { [weak self] free in self?.handleLowStorage(free: free) ?? false }
        refreshDiskAccess()
        // Verification hook: lets a capture run show the whole-Mac result screen.
        if ProcessInfo.processInfo.arguments.contains("--run-full-check") {
            startFullCheck()
            Task {
                while fullCheck.running || triage.computing { try? await Task.sleep(for: .milliseconds(500)) }
                try? await Task.sleep(for: .seconds(1))
                AppDelegate.capture(name: "fullcheck")
            }
        }
        UNUserNotificationCenter.current().delegate = AlertCenter.shared
        AlertCenter.shared.registerActions()
        startStorageUpdates()
        if !ProcessInfo.processInfo.arguments.contains("--demo-fixtures") { features.loadHistory() }
        scheduledScans.start()
        if !ProcessInfo.processInfo.arguments.contains("--demo-fixtures") {
            if page == .trash { inspectTrash() }
            if page == .docker { inspectDocker() }
        }
    }
    func showMainWindow(_ page: Page? = nil) {
        mainWindowVisible = true
        if let page { self.page = page }; statusController?.close(); openMainWindow?(); NSApp.activate(ignoringOtherApps: true)
    }
    func prepareRecovery(_ kind: RecoveryTask.Kind) { recovery = RecoveryTask(kind: kind); page = .permissions }
    func chooseFolderForRecovery() {
        guard let task = recovery else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Use folder and retry"
        if case .storage(let root) = task.kind { panel.directoryURL = root }
        if panel.runModal() == .OK, let chosen = panel.url {
            FolderAccess.shared.remember(chosen)
            if case .storage(let original) = task.kind, original.standardizedFileURL != chosen.standardizedFileURL, !original.standardizedFileURL.path.hasPrefix(chosen.standardizedFileURL.path + "/") { recovery = RecoveryTask(kind: .storage(chosen)) }
            retryRecovery()
        }
    }
    func retryRecovery() {
        guard let recovery else { return }; FolderAccess.shared.restore(); self.recovery = nil
        switch recovery.kind { case .storage(let url): page = .storage; scan(url, force: true); case .trash: page = .trash; inspectTrash(); case .findSpace: page = .findSpace; findSpace() }
    }
    func sleep() { sleeping = true; reconcileLiveFolder(); features.monitor.sleep(); scheduledScans.pause(); scanner.invalidate(); saveSession() }
    func wake() { sleeping = false; features.monitor.wake(); scheduledScans.resume(); scanner.invalidate(); storageDirty = result != nil; reconcileLiveFolder() }
    func startDockerAndRefresh() {
        guard !dockerLoading else { return }
        dockerLoading = true; dockerStarting = true; dockerError = "Waiting for Docker Desktop to become reachable…"
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
        dockerStartTask = Task {
            for _ in 0..<8 {
                guard !Task.isCancelled else { return }
                let report = await Task.detached(priority: .utility) { DockerInspection.inspect() }.value
                guard !Task.isCancelled else { return }
                if report.reachable { dockerLoading = false; dockerStarting = false; inspectDocker(); return }
                try? await Task.sleep(for: .seconds(3))
            }
            dockerLoading = false; dockerStarting = false; dockerError = "Docker did not become reachable. Check Docker Desktop, then refresh. No cleanup ran."
        }
    }
    func cancelDockerWait() { dockerStartTask?.cancel(); dockerStartTask = nil; dockerLoading = false; dockerStarting = false; dockerError = "Stopped waiting. Docker may continue starting; refresh when ready." }
    func refreshResources() { let id = UUID(); resourceRefreshID = id; Task { let reading = await Task.detached(priority: .utility) { MachineService.snapshot() }.value; guard resourceRefreshID == id else { return }; resources = reading } }
    func chooseFolder() {
        FolderAccess.shared.chooseFolder(prompt: "Scan folder") { [weak self] url in
            guard let self else { return }
            self.scan(url)
            self.page = .storage
        }
    }

    func scan(_ url: URL? = nil, force: Bool = false, automatic: Bool = false) {
        guard !quitWhenIdle else { return }
        scanToken.cancel(); let token = ScanCancellation(); scanToken = token
        let generation = UUID(); scanGeneration = generation
        UIResponsiveness.mark(.scanQueued)
        if !automatic { treeResetToken = UUID() }
        if let url { scanRoot = url }
        let root = scanRoot; if !automatic { folderFreshness.cancelPending() }; scanning = true; if !automatic { selected.removeAll() }; storageDirty = false; scanState = "Refreshing…"
        reconcileLiveFolder()
        Log.scan.info("Folder scan starting: automatic=\(automatic, privacy: .public) force=\(force, privacy: .public)")
        Task {
            let output = await DiskWork.run(automatic ? "Updating visible folder" : "Scanning folder", priority: automatic ? .background : .foreground, cancellation: token) { [scanner] in
                UIResponsiveness.mark(.scanStarted)
                let result = scanner.scan(root, token: token, force: force)
                UIResponsiveness.mark(.scanReturned)
                return result
            }
            let r = output.result
            guard scanGeneration == generation else { return }
            if automatic { let identities = Dictionary(uniqueKeysWithValues: (result?.items ?? []).filter { selected.contains($0.id) }.map { ($0.id, $0.identity) }); selected = Set(r.items.filter { item in identities[item.id].map { $0 == item.identity } == true && !item.incomplete }.map(\.id)) }
            result = r; resultMeasured = output.date
            UIResponsiveness.mark(.scanPublished)
            scanState = token.cancelled ? "Stopped — partial results" : r.limited ? "Scan limit reached — partial results" : r.skipped > 0 ? "Access incomplete — partial results" : storageDirty ? "Folder changed — update pending" : output.reused > 0 ? "\(output.reused) items reused · cached estimate; Full scan measures again" : "Measured now"
            Log.scan.info("Folder scan finished: items=\(r.items.count, privacy: .public) visited=\(r.visited, privacy: .public) skipped=\(r.skipped, privacy: .public) limited=\(r.limited, privacy: .public) reused=\(output.reused, privacy: .public)")
            if r.skipped > 0 { Log.access.notice("Scan could not read \(r.skipped, privacy: .public) entries; access issues=\(r.accessIssues.count, privacy: .public)") }
            if output.reused == 0 && !automatic { features.saveScan(root: root, result: r) }; scanning = false; refreshResources(); if !automatic { scheduleSessionSave() }; folderFreshness.finished()
            // Background refreshes repaint the same folder; only an explicit scan
            // is a new question worth re-ranking and re-asking about.
            if !automatic { triage.refresh(items: r.items, rootName: root.lastPathComponent, signals: triageSignals()) }
        }
    }
    func cancelScan() { scanToken.cancel(); folderFreshness.cancelPending() }
    func cancelCaches() { cacheToken.cancel() }
    /// Opens a measured folder in Files with the tree view selected.
    func browseTree(_ url: URL, force: Bool = true) {
        UserDefaults.standard.set(true, forKey: "nuke.filesViewMode")
        scan(url, force: force)
        page = .storage
    }
    func scanCaches() {
        guard !cacheScanning else { return }
        cacheScanning = true; cacheOutcome = "Measuring…"; caches = []; let token = ScanCancellation(); cacheToken = token
        refreshOpenFiles()
        let generation = UUID(); cacheGeneration = generation
        Task {
            for rule in CacheRule.all {
                let m = await DiskWork.run("Measuring " + rule.name, cancellation: token) { DiskScanner.cache(rule, cancellation: token) }
                guard generation == cacheGeneration else { return }; caches.append(m)
                if token.cancelled { break }
            }
            cacheScanning = false
            cacheOutcome = token.cancelled ? "Stopped — partial results" : caches.contains { $0.skipped > 0 } ? "Inspection finished — access gaps" : caches.contains { $0.item?.incomplete == true } ? "Scan limit reached — partial results" : "Inspection finished"
            let measured = caches.compactMap(\.item)
            Log.scan.info("Developer cache scan finished: locations=\(self.caches.count, privacy: .public) measured=\(measured.count, privacy: .public)")
            triage.refresh(items: measured, rootName: "Developer", signals: triageSignals())
        }
    }
    func refreshPorts() {
        guard !portsLoading else { return }
        portsLoading = true; portsError = nil
        Task {
            let report = await Task.detached(priority: .utility) { PortInspection.inspect() }.value
            listeningPorts = report.rows
            portsError = report.error
            portsUpdated = Date()
            portsLoading = false
        }
    }

    func refreshProjectActivity() {
        guard !projectActivityLoading else { return }
        projectActivityLoading = true
        Task {
            let processReport = await Task.detached(priority: .utility) { ProcessService.snapshot() }.value
            let portReport = await Task.detached(priority: .utility) { PortInspection.inspect() }.value
            processes = processReport.rows
            processError = processReport.error
            portsError = portReport.error
            listeningPorts = portReport.rows
            portsUpdated = Date()
            let processPids = processReport.rows.filter { ProjectActivityDetector.isDevelopmentProcess($0) }.map(\.pid)
            let portPids = portReport.rows.map(\.pid)
            let pids = Array(Set(processPids + portPids)).prefix(48)
            var cwd: [Int32: String] = [:]
            await withTaskGroup(of: (Int32, String?).self) { group in
                for pid in pids {
                    group.addTask { (pid, PortInspection.currentDirectory(pid: pid)) }
                }
                for await (pid, directory) in group {
                    if let directory { cwd[pid] = directory }
                }
            }
            var merged = ProjectActivityDetector.activeWithPorts(projects: features.projects, ports: portReport.rows, cwd: cwd)
            for (id, names) in ProjectActivityDetector.activeWithProcessCWD(projects: features.projects, processes: processReport.rows, cwd: cwd) {
                merged[id, default: []].append(contentsOf: names)
            }
            projectPortActivity = merged.mapValues { Array(Set($0)).sorted() }
            processLoading = false
            projectActivityLoading = false
        }
    }

    func refreshProcesses() {
        guard !processLoading else { return }; processLoading = true
        Task { let report = await Task.detached(priority: .utility) { ProcessService.snapshot() }.value; processes = report.rows; processError = report.error; processLoading = false; refreshResources() }
    }
    func inspectDocker() {
        guard !quitWhenIdle else { return }
        guard !dockerLoading else { return }; dockerLoading = true; dockerError = nil; dockerReachable = false
        Task {
            let report = await Task.detached(priority: .utility) { DockerInspection.inspect() }.value
            let disks = await Task.detached(priority: .utility) { DockerInspection.localDisks() }.value
            if report.context != dockerContext { docker = []; dockerVolumes = []; dockerUpdated = nil }
            dockerContext = report.context; dockerReachable = report.reachable; dockerError = report.note; dockerDisks = disks
            dockerVolumes = report.volumes; dockerVolumeError = report.volumeError
            if report.reachable {
                let updated = Date()
                docker = report.rows; dockerUpdated = updated
                if let data = try? JSONEncoder().encode(DockerSavedUsage(context: report.context, rows: report.rows, date: updated, volumes: report.volumes)) { UserDefaults.standard.set(data, forKey: "nuke.dockerUsage") }
            }
            dockerLoading = false
        }
    }

    func pruneDocker(_ kind: String, reviewedContext: String) {
        guard !actionBusy, !dockerLoading, dockerReachable, !reviewedContext.isEmpty, reviewedContext == dockerContext else { return }
        let args: [String]
        switch kind {
        case "Build cache": args = ["builder", "prune", "--force"]
        case "Dangling images": args = ["image", "prune", "--force"]
        case "Stopped containers": args = ["container", "prune", "--force"]
        default: return
        }
        actionBusy = true
        Task {
            let freeBefore = await Task.detached(priority: .utility) { MachineService.snapshot().freeDisk }.value
            let r = await Task.detached { CommandRunner.run("/usr/bin/env", ["docker", "--context", reviewedContext] + args, timeout: 120) }.value
            let detail = "Context: \(reviewedContext)\n\(r.output.prefix(3000))"
            let freeAfter = await Task.detached(priority: .utility) { MachineService.snapshot().freeDisk }.value
            features.receipt(CleanupReceipt(date: Date(), title: "Docker cleanup: \(kind)", items: [.init(originalPath: "Docker context: " + reviewedContext, trashPath: nil, size: 0, success: r.status == 0, outcome: detail)], freeBefore: freeBefore, freeAfter: freeAfter, undo: "Docker prune is permanent; no Trash restoration. CLI output above reports Docker's reclaimed-space result. Local disk change may be unrelated when the context is remote."))
            record(r.status == 0 ? "Docker cleanup: \(kind)" : "Docker cleanup failed", detail: detail)
            actionBusy = false
        }
    }
    func deleteSimulator(_ device: SimulatorDevice) {
        guard !actionBusy, !features.deviceLoading else { return }
        actionBusy = true; features.simulatorActionBusy = true; features.simulatorActionResult = nil
        Task {
            let result = await DiskWork.run("Deleting simulator") { EmulatorCleanup.delete(device) }
            features.receipt(CleanupReceipt(date: Date(), title: "Simulator deletion", items: [.init(originalPath: "Simulator: " + device.name + " (" + device.id + ")", trashPath: nil, size: 0, success: result.success, outcome: result.message)], freeBefore: nil, freeAfter: nil, undo: "Simulator deletion is permanent. Installed apps and test data cannot be recovered from Trash. The shared runtime is retained."))
            features.simulatorActionResult = result.message; features.simulatorActionBusy = false; actionBusy = false
            features.scanDevices()
        }
    }
    func reviewTrash(_ items: [DiskItem], proofs: [DuplicateProof] = [], cacheContents: CacheRule? = nil, folderContents: DiskItem? = nil) {
        guard !actionBusy else { return }; actionBusy = true
        pendingTrash = []; pendingTrashSelection = []; duplicateProofs = []; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = []
        reviewPreparing = true; let token = ScanCancellation(); reviewToken = token
        let scopes = FolderAccess.shared.cleanupScopes
        let developerScopes = features.developerScopes
        Task {
            let preparation = await DiskWork.run("Preparing cleanup review", cancellation: token) { () -> ReviewPreparation in
                if let cacheContents {
                    return ReviewPlanner.prepareCacheContents(cacheContents, scopes: scopes, token: token, developerScopes: developerScopes)
                }
                if let folderContents {
                    return ReviewPlanner.prepareFolderContents(folderContents, scopes: scopes, token: token, developerScopes: developerScopes)
                }
                return ReviewPlanner.prepare(items, scopes: scopes, token: token, developerScopes: developerScopes)
            }
            guard reviewToken === token else { return }
            reviewPreparing = false; actionBusy = false
            guard !token.cancelled else { return }
            pendingBlocked = preparation.blocked
            guard !preparation.items.isEmpty else {
                pendingEvidence = [:]; pendingWarnings = []; pendingTrash = []
                showTrashReview = !pendingBlocked.isEmpty
                if pendingBlocked.isEmpty { message = preparation.failures.joined(separator: "\n") }
                return
            }
            Log.cleanup.info("Review prepared: eligible=\(preparation.items.count, privacy: .public) blocked=\(preparation.blocked.count, privacy: .public) warnings=\(preparation.warnings.count, privacy: .public)")
            duplicateProofs = proofs
            pendingEvidence = preparation.evidence
            pendingWarnings = preparation.warnings
            pendingTrash = preparation.items
            pendingTrashSelection = folderContents == nil ? Set(preparation.items.map(\.id)) : []
            showTrashReview = !pendingTrash.isEmpty
        }
    }

    func cancelReview() { reviewToken.cancel(); reviewPreparing = false; actionBusy = false; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = [] }
    func trashReviewed() {
        let items = selectedPendingTrash
        guard !actionBusy, !items.isEmpty else { return }
        showTrashReview = false
        actionBusy = true
        let proofs = duplicateProofs.filter { pendingTrashSelection.contains($0.duplicate.id) }
        let allowedRoots = FolderAccess.shared.cleanupScopes
        let developerScopes = features.developerScopes
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        Log.cleanup.notice("Executing reviewed cleanup: items=\(items.count, privacy: .public) bytes=\(items.reduce(0) { $0 + $1.size }, privacy: .public)")
        Task {
            let receipt = await DiskWork.run { ReceiptService.moveToTrash(items, proofs: proofs, runningAppPaths: running, allowedRoots: allowedRoots, developerScopes: developerScopes) }
            let moved = receipt.items.filter(\.success).count
            Log.cleanup.notice("Cleanup finished: moved=\(moved, privacy: .public) failed=\(receipt.items.count - moved, privacy: .public)")
            features.receipt(receipt)
            let detail = receipt.items.map { "\($0.success ? "Moved to Trash" : "Failed"): \($0.originalPath) · \($0.outcome)" }.joined(separator: "\n")
            cleanupBasket.removeMoved(receipt.items.filter(\.success).map(\.originalPath))
            personalFilesMoved(receipt.items.filter(\.success).map(\.originalPath))
            record("File cleanup", detail: detail); actionBusy = false; pendingTrash = []; pendingTrashSelection = []; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = []; duplicateProofs = []

        }
    }

    func restoreReceiptItem(_ item: ReceiptItem, onFailure: ((String) -> Void)? = nil) {
        guard !actionBusy, let current = features.receipts.lazy.flatMap(\.items).first(where: { $0.id == item.id }),
              current.success, current.restoredAt == nil, current.restoreEvidence != nil else { return }
        actionBusy = true
        Task {
            let outcome = await DiskWork.run("Restoring from Trash") { Result { try ReceiptRestore.restore(current) } }
            switch outcome {
            case .success:
                features.markRestored(current.id)
                record("Restored item", detail: "Restored " + current.originalPath + " from Trash.")
            case .failure(let error):
                if let onFailure { onFailure(error.localizedDescription) }
                else { message = error.localizedDescription }
            }
            actionBusy = false
        }
    }

    func exportPendingPlan() {
        let items = selectedPendingTrash
        guard !items.isEmpty else { return }
        let plan = CleanupPlan(
            generatedAt: Date(),
            note: "Dry run only. No files were moved. Each normal cleanup moves reviewed items to macOS Trash; space is reclaimed only after Trash is emptied.",
            totalLogicalSize: items.reduce(0) { $0 + $1.size },
            items: items.map { .init(path: $0.url.path, size: $0.size, directory: $0.directory, evidence: pendingEvidence[$0.id]) },
            warnings: pendingWarnings
        )
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Nuke Sweep-cleanup-plan.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(plan).write(to: url, options: .atomic)
        } catch { message = "Could not export the cleanup plan: " + error.localizedDescription }
    }

    private var trashInspectionToken = ScanCancellation()
    func cancelTrashInspection() { trashInspectionToken.cancel() }
    func inspectTrash() {
        guard !trashLoading, !actionBusy else { return }
        trashInspectionToken = ScanCancellation(); let token = trashInspectionToken
        trashLoading = true; trashError = nil; trashSnapshot = nil; trashSelected = []
        Task {
            do {
                let outcome = await DiskWork.run("Inspecting Trash", cancellation: token) { Result { try TrashService.current.inspect(token: token) } }; let snapshot = try outcome.get()
                guard trashInspectionToken === token else { return }; trashSnapshot = snapshot; trashUpdated = Date()
            } catch { guard trashInspectionToken === token else { return }; trashError = error.localizedDescription }
            trashLoading = false
        }
    }
    func permanentlyDeleteTrash(_ entries: [TrashEntry], rootIdentity: FileIdentity) {
        guard !actionBusy, !entries.isEmpty, let snapshot = trashSnapshot, snapshot.complete, snapshot.rootIdentity == rootIdentity,
              entries.allSatisfy({ entry in snapshot.entries.contains { $0.id == entry.id && $0.fingerprint == entry.fingerprint } }) else { return }
        actionBusy = true
        Task {
            let freeBefore = await Task.detached(priority: .utility) { MachineService.snapshot().freeDisk }.value
            let outcomes = await DiskWork.run { TrashService.current.deleteReviewed(entries, rootIdentity: rootIdentity) }
            let detail = outcomes.joined(separator: "\n")
            let freeAfter = await Task.detached(priority: .utility) { MachineService.snapshot().freeDisk }.value
            features.receipt(CleanupReceipt(date: Date(), title: "Permanent Trash cleanup", items: entries.enumerated().map { index, entry in let text = outcomes.count == entries.count ? outcomes[index] : (outcomes.first ?? "Cleanup did not return an outcome"); return .init(originalPath: entry.item.url.path, trashPath: nil, size: entry.item.size, success: text.hasPrefix("Permanently deleted:"), outcome: text) }, freeBefore: freeBefore, freeAfter: freeAfter, undo: "Permanent deletion cannot be restored through Trash. Check your own backups if recovery is needed."))
            record("Trash cleanup", detail: detail); actionBusy = false

        }
    }
    func record(_ title: String, detail: String) {
        activities.insert(.init(date: Date(), title: title, detail: detail), at: 0); activities = Array(activities.prefix(100))
        if let d = try? JSONEncoder().encode(activities) { UserDefaults.standard.set(d, forKey: "nuke.history") }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

extension AppModel {
    func startStorageUpdates() {
        guard !storageUpdatesStarted else { return }; storageUpdatesStarted = true
        folderFreshness.canRefresh = { [weak self] in guard let self else { return false }; return !self.scanning && !self.actionBusy && !self.showTrashReview && self.mainWindowVisible && !self.sleeping }
        folderFreshness.onChange = { [weak self] in guard let self else { return }; self.storageDirty = true; if !self.scanning { self.scanState = "Folder changed — updating…" } }
        folderFreshness.onRefresh = { [weak self] in self?.scan(automatic: true) }
        reconcileLiveFolder()
    }
    func reconcileLiveFolder() {
        guard storageUpdatesStarted else { return }
        let active = mainWindowVisible && !sleeping && page == .storage && (result != nil || scanning)
        if !active && result != nil { storageDirty = true }
        folderFreshness.configure(active ? scanRoot : nil)
        storageIsLive = active && folderFreshness.available
        if active && storageDirty && !scanning && !actionBusy { folderFreshness.changed() }
    }
    func refreshDirtyVisibleInventory() {
        guard storageUpdatesStarted, mainWindowVisible, !actionBusy, !quitWhenIdle else { return }
        features.refreshDirtyStorage(page)
    }
    /// Every cleanup endpoint emits a receipt, including failures and partial outcomes.
    func refreshAfterMutation() {
        guard !quitWhenIdle else { return }
        scanner.invalidate(); storageDirty = result != nil
        quickToken.cancel(); _ = newQuickToken(); quick = QuickScanState()
        cacheToken.cancel(); cacheGeneration = UUID(); cacheScanning = false; caches = []
        trashInspectionToken.cancel(); trashInspectionToken = ScanCancellation(); trashLoading = false; trashSnapshot = nil; trashSelected = []
        features.invalidateStorageInventories()
        refreshResources(); features.monitor.storageDidChange()
        if result != nil { scan(force: true, automatic: true) }
        if page == .developer || page == .overview { scanCaches() }
        if page == .findSpace { findSpace() }
        if page == .trash { inspectTrash() }
        if page == .docker { inspectDocker() }
        refreshDirtyVisibleInventory()
    }
}
