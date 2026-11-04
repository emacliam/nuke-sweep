import SwiftUI
import AppKit
import Combine
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    let features = FeatureModel()
    @Published var mainWindowVisible = true { didSet { if oldValue != mainWindowVisible { reconcileLiveFolder(); if mainWindowVisible { refreshDirtyVisibleInventory() } } } }
    @Published var storageIsLive = false
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
    @Published var focusedStorageItem: String? { didSet { scheduleSessionSave() } }
    @Published var resultMeasured: Date?
    @Published var scanState = "Not scanned"
    @Published var recovery: RecoveryTask?
    @Published var reviewPreparing = false
    private var reviewToken = ScanCancellation()
    private var watchSchedule = WatchSchedule()
    private var watchAlertBaseline: Int64?
    private var dockerStartTask: Task<Void, Never>?
    @Published var finishedReceipt: CleanupReceipt?
    @Published var quick = QuickScanState()
    /// Last completed pass, kept while a new pass runs so quitting mid-scan cannot erase evidence.
    private var completedQuick: QuickScanState?
    @Published var quickSelected = Set<String>()
    var quickSelectedItems: [DiskItem] { quick.entries.filter { quickSelected.contains($0.id) && !$0.item.incomplete }.map(\.item) }
    private let scanner = IncrementalScanner()
    private var quickToken = ScanCancellation()
    func isCurrentQuick(_ token: ScanCancellation) -> Bool { quickToken === token }
    func quickTokenForScan() -> ScanCancellation { quickToken }
    func newQuickToken() -> ScanCancellation { quickToken = ScanCancellation(); return quickToken }
    func stopFindSpace() { quickToken.cancel() }
    private var duplicateProofs: [DuplicateProof] = []
    @Published var page: Page = .findSpace {
        didSet { if oldValue != page { filters[oldValue.rawValue] = search; search = filters[page.rawValue] ?? ""; scheduleSessionSave(); reconcileLiveFolder(); refreshDirtyVisibleInventory() } }
    }
    @Published var resources = ResourceSnapshot()
    @Published var result: ScanResult?
    @Published var scanRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads") { didSet { scheduleSessionSave(); reconcileLiveFolder() } }
    @Published var scanning = false
    @Published var cacheScanning = false
    @Published var cacheOutcome = "Not scanned"
    @Published var caches: [CacheMeasurement] = []
    @Published var processes: [ProcessRow] = []
    @Published var processLoading = false
    @Published var processError: String?
    @Published var docker: [DockerUsage] = []
    @Published var dockerContext = ""
    @Published var dockerLoading = false
    @Published var dockerError: String?
    @Published var dockerUpdated: Date?
    @Published var dockerReachable = false
    @Published var dockerStarting = false
    @Published var dockerDisks: [DiskItem] = []
    @Published var selected = Set<String>()
    /// Bumped for manual scans so the Files tree can drop stale expansions without collapsing on periodic refresh.
    @Published var treeResetToken = UUID()
    @Published var search = "" { didSet { filters[page.rawValue] = search; scheduleSessionSave() } }
    /// Incremented by the ⌘F command so whichever filter is on screen can take focus.
    @Published var focusFilterRequest = 0
    @Published var pendingTrash: [DiskItem] = []
    @Published var pendingEvidence: [String: CleanupEvidence] = [:]
    @Published var pendingWarnings: [String] = []
    @Published var restoredReceiptItems = Set<UUID>()
    @Published var pendingBlocked: [ReviewBlockedItem] = []
    @Published var showTrashReview = false
    var quitWhenIdle = false
    @Published var actionBusy = false {
        didSet { if !actionBusy && quitWhenIdle { FilePersistence.flush(); NSApp.reply(toApplicationShouldTerminate: true) }; if !actionBusy && pendingMutationRefresh && !quitWhenIdle { pendingMutationRefresh = false; refreshAfterMutation() } }
    }
    @Published var message: String?
    @Published var activities: [Activity] = []
    @Published var watchURL: URL?
    @Published var watching = false
    @Published var watchEvents = 0
    @Published var watchChanged: Date?
    @Published var watchBaseline: Int64?
    @Published var watchSize: Int64?
    @Published var watchScanning = false
    @Published var watchError: String?
    @Published var trashSnapshot: TrashSnapshot?
    @Published var trashLoading = false
    @Published var trashError: String?
    @Published var trashSelected = Set<String>()
    @Published var trashUpdated: Date?
    private var scanToken = ScanCancellation()
    private var cacheToken = ScanCancellation()
    private var cacheGeneration = UUID()
    private var watchToken = ScanCancellation()
    private var recursiveWatch: RecursiveChanges?
    private var watchTask: Task<Void, Never>?
    private var watchTimer: Timer?
    private var scanGeneration = UUID()
    private var watchGeneration = UUID()
    var visibleItems: [DiskItem] { (result?.items ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var visibleProcesses: [ProcessRow] { processes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.pid).contains(search) } }
    var selectedItems: [DiskItem] { (result?.items ?? []).filter { selected.contains($0.id) } }
    var cacheBytes: Int64 { caches.reduce(0) { $0 + ($1.item?.size ?? 0) } }
    init(restoring: Bool = true) {
        persistSessionEnabled = restoring
        if let data = UserDefaults.standard.data(forKey: "nuke.history"), let stored = try? JSONDecoder().decode([Activity].self, from: data) { activities = stored }
        if restoring { refreshResources() }
        if restoring, let data = UserDefaults.standard.data(forKey: "nuke.dockerUsage"), let saved = try? JSONDecoder().decode(DockerSavedUsage.self, from: data) { docker = saved.rows; dockerContext = saved.context; dockerUpdated = saved.date; dockerError = "Saved Docker measurement — refresh to check the engine." }
        features.onReceipt = { [weak self] receipt in
            guard let self else { return }; self.finishedReceipt = receipt
            self.pendingMutationRefresh = true
            if !self.actionBusy { self.pendingMutationRefresh = false; self.refreshAfterMutation() }
        }
        if restoring, let data = UserDefaults.standard.data(forKey: "nuke.workspace"), let saved = try? JSONDecoder().decode(WorkspaceState.self, from: data) {
            filters = saved.filters; page = saved.page == "AI storage" ? .ai : (saved.page == "Overview" ? .findSpace : (Page(rawValue: saved.page) ?? .findSpace)); scanRoot = saved.root
            search = saved.filters[page.rawValue] ?? ""; focusedStorageItem = saved.focusedItem
            result = saved.snapshot; resultMeasured = saved.measured
            if result != nil { scanState = "Saved measurement — refresh before review" }
            if let saved = saved.quick {
                quick = saved; quick.busy = false; completedQuick = saved
                if quick.measured == nil { quick.step = "Interrupted — the last pass did not finish" }
                quickSelected = []
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
        UNUserNotificationCenter.current().delegate = AlertCenter.shared
        AlertCenter.shared.registerActions()
        startStorageUpdates()
        features.loadHistory()
        if page == .processes { refreshProcesses() }
        if page == .trash { inspectTrash() }
        if page == .docker { inspectDocker() }
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
    func sleep() { sleeping = true; reconcileLiveFolder(); features.monitor.sleep(); scanner.invalidate(); watchToken.cancel(); watchGeneration = UUID(); watchScanning = false; watchSchedule.clear(); if watching { watchSchedule.changed() }; saveSession() }
    func wake() { sleeping = false; features.monitor.wake(); scanner.invalidate(); storageDirty = result != nil; reconcileLiveFolder(); if watching { scheduleWatchScan() } }
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
    func chooseFolder(forWatch: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = forWatch ? "Watch folder" : "Scan folder"
        if panel.runModal() == .OK, let url = panel.url { FolderAccess.shared.remember(url); if forWatch { startWatching(url) } else { scan(url); page = .storage } }
    }
    func scan(_ url: URL? = nil, force: Bool = false, automatic: Bool = false) {
        guard !quitWhenIdle else { return }
        scanToken.cancel(); let token = ScanCancellation(); scanToken = token
        let generation = UUID(); scanGeneration = generation
        if !automatic { treeResetToken = UUID() }
        if let url { scanRoot = url }
        let root = scanRoot; if !automatic { folderFreshness.cancelPending() }; scanning = true; if !automatic { selected.removeAll() }; storageDirty = false; scanState = "Refreshing…"
        reconcileLiveFolder()
        Task {
            let output = await DiskWork.run(automatic ? "Updating visible folder" : "Scanning folder", priority: automatic ? .background : .foreground, cancellation: token) { [scanner] in scanner.scan(root, token: token, force: force) }
            let r = output.result
            guard scanGeneration == generation else { return }
            if automatic { let identities = Dictionary(uniqueKeysWithValues: (result?.items ?? []).filter { selected.contains($0.id) }.map { ($0.id, $0.identity) }); selected = Set(r.items.filter { identities[$0.id] != nil && identities[$0.id]! == $0.identity && !$0.incomplete }.map(\.id)) }
            result = r; resultMeasured = output.date
            scanState = token.cancelled ? "Stopped — partial results" : r.limited ? "Scan limit reached — partial results" : r.skipped > 0 ? "Access incomplete — partial results" : storageDirty ? "Folder changed — update pending" : output.reused > 0 ? "\(output.reused) items reused · cached estimate; Full scan measures again" : "Measured now"
            if output.reused == 0 && !automatic { features.saveScan(root: root, result: r) }; scanning = false; refreshResources(); if !automatic { scheduleSessionSave() }; folderFreshness.finished()
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
        let generation = UUID(); cacheGeneration = generation
        Task {
            for rule in CacheRule.all {
                let m = await DiskWork.run("Measuring " + rule.name, cancellation: token) { DiskScanner.cache(rule, cancellation: token) }
                guard generation == cacheGeneration else { return }; caches.append(m)
                if token.cancelled { break }
            }
            cacheScanning = false
            cacheOutcome = token.cancelled ? "Stopped — partial results" : caches.contains { $0.skipped > 0 } ? "Inspection finished — access gaps" : caches.contains { $0.item?.incomplete == true } ? "Scan limit reached — partial results" : "Inspection finished"
        }
    }
    func refreshProcesses() {
        guard !processLoading else { return }; processLoading = true
        Task { let report = await Task.detached(priority: .utility) { ProcessService.snapshot() }.value; processes = report.rows; processError = report.error; processLoading = false; refreshResources() }
    }
    func terminate(_ row: ProcessRow) {
        Task {
            let current = await Task.detached { ProcessService.list().first { $0.pid == row.pid } }.value
            guard let current, current.started == row.started, current.command == row.command, row.owner == getuid(), row.pid != getpid(), row.pid > 1 else { message = "The process changed, belongs to another user, or is protected. Refresh the list."; return }
            if let app = NSRunningApplication(processIdentifier: row.pid) {
                message = app.terminate() ? "Quit requested for \(row.name). Unsaved work may require attention in the app." : "The app did not accept the quit request. Use Activity Monitor to inspect it."
            } else {
                message = kill(row.pid, SIGTERM) == 0 ? "Termination requested for \(row.name)." : "Could not terminate the process: \(String(cString: strerror(errno)))."
            }
            record("Quit requested", detail: "\(row.name) · PID \(row.pid)"); refreshProcesses()
        }
    }
    func inspectDocker() {
        guard !quitWhenIdle else { return }
        guard !dockerLoading else { return }; dockerLoading = true; dockerError = nil; dockerReachable = false
        Task {
            let report = await Task.detached(priority: .utility) { DockerInspection.inspect() }.value
            let disks = await Task.detached(priority: .utility) { DockerInspection.localDisks() }.value
            if report.context != dockerContext { docker = []; dockerUpdated = nil }
            dockerContext = report.context; dockerReachable = report.reachable; dockerError = report.note; dockerDisks = disks
            if report.reachable {
                docker = report.rows; dockerUpdated = Date()
                if let data = try? JSONEncoder().encode(DockerSavedUsage(context: report.context, rows: report.rows, date: dockerUpdated!)) { UserDefaults.standard.set(data, forKey: "nuke.dockerUsage") }
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
    func reviewTrash(_ items: [DiskItem], proofs: [DuplicateProof] = [], cacheContents: CacheRule? = nil) {
        guard !actionBusy else { return }; actionBusy = true
        pendingTrash = []; duplicateProofs = []; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = []
        reviewPreparing = true; let token = ScanCancellation(); reviewToken = token
        let scopes = FolderAccess.shared.cleanupScopes
        Task {
            let preparation = await DiskWork.run("Preparing cleanup review", cancellation: token) { () -> ReviewPreparation in
                if let cacheContents {
                    return ReviewPlanner.prepareCacheContents(cacheContents, scopes: scopes, token: token)
                }
                return ReviewPlanner.prepare(items, scopes: scopes, token: token)
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
            duplicateProofs = proofs
            pendingEvidence = preparation.evidence
            pendingWarnings = preparation.warnings
            pendingTrash = preparation.items; showTrashReview = !pendingTrash.isEmpty
        }
    }

    func cancelReview() { reviewToken.cancel(); reviewPreparing = false; actionBusy = false; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = [] }
    func trashReviewed() {
        guard !actionBusy, !pendingTrash.isEmpty else { return }; let items = pendingTrash; showTrashReview = false; actionBusy = true
        let proofs = duplicateProofs
        let allowedRoots = FolderAccess.shared.cleanupScopes
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        Task {
            let receipt = await DiskWork.run { ReceiptService.moveToTrash(items, proofs: proofs, runningAppPaths: running, allowedRoots: allowedRoots) }
            features.receipt(receipt)
            let detail = receipt.items.map { "\($0.success ? "Moved to Trash" : "Failed"): \($0.originalPath) · \($0.outcome)" }.joined(separator: "\n")
            record("File cleanup", detail: detail); actionBusy = false; pendingTrash = []; pendingEvidence = [:]; pendingWarnings = []; pendingBlocked = []; duplicateProofs = []

        }
    }

    /// Restores one successful receipt item from Trash. Refuses to overwrite an existing
    /// original path and never invents a directory. The Trash copy is the only source.
    func restoreReceiptItem(_ item: ReceiptItem) {
        guard !actionBusy, item.success, let trashPath = item.trashPath else { return }
        actionBusy = true
        Task {
            let failure = await DiskWork.run("Restoring from Trash") { () -> String? in
                let trashURL = URL(fileURLWithPath: trashPath), originalURL = URL(fileURLWithPath: item.originalPath)
                let fm = FileManager.default
                guard fm.fileExists(atPath: trashURL.path) else { return "The Trash copy is no longer present. Check Trash in Finder." }
                guard !fm.fileExists(atPath: originalURL.path) else { return "The original path already exists. Nuke Sweep will not overwrite it." }
                guard fm.fileExists(atPath: originalURL.deletingLastPathComponent().path) else { return "The original parent folder no longer exists. Recreate it before restoring, or use Finder." }
                do { try fm.moveItem(at: trashURL, to: originalURL); return nil }
                catch { return "Could not restore \(item.originalPath): " + error.localizedDescription }
            }
            if let failure { message = failure }
            else { restoredReceiptItems.insert(item.id); record("Restored item", detail: "Restored \(item.originalPath) from Trash.") }
            actionBusy = false
        }
    }

    func exportPendingPlan() {
        guard !pendingTrash.isEmpty else { return }
        let plan = CleanupPlan(
            generatedAt: Date(),
            note: "Dry run only. No files were moved. Each normal cleanup moves reviewed items to macOS Trash; space is reclaimed only after Trash is emptied.",
            totalLogicalSize: pendingTrash.reduce(0) { $0 + $1.size },
            items: pendingTrash.map { .init(path: $0.url.path, size: $0.size, directory: $0.directory, evidence: pendingEvidence[$0.id]) },
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
        guard !actionBusy, !entries.isEmpty, let snapshot = trashSnapshot, snapshot.rootIdentity == rootIdentity,
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
    func startWatching(_ url: URL) {
        stopWatching(); watchURL = url; watchEvents = 0; watchBaseline = nil; watchAlertBaseline = nil; watchSize = nil; watchError = nil
        let eventGeneration = watchGeneration
        recursiveWatch = RecursiveChanges(url) { [weak self] in
            DispatchQueue.main.async { guard let self, self.watching, self.watchGeneration == eventGeneration else { return }; self.watchEvents += 1; self.watchChanged = Date(); self.scheduleWatchScan() }
        }
        watching = recursiveWatch?.available == true
        if watching {
            measureWatch()

        } else { watchError = "Nuke Sweep could not watch this folder. Choose a readable location." }
    }
    func scheduleWatchScan() {
        watchSchedule.changed()
        watchTask?.cancel(); watchTask = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { measureWatch() } }
    }
    func measureWatch() {
        guard watching, let url = watchURL, watchSchedule.begin() else { return }
        watchScanning = true; let token = ScanCancellation(); watchToken = token; let generation = watchGeneration
        Task {
            let r = await DiskWork.run("Watching folder", priority: .background, cancellation: token) { DiskScanner.scan(url, cancellation: token) }
            guard generation == watchGeneration else { return }
            watchSize = r.logical; if watchBaseline == nil { watchBaseline = r.logical }; watchScanning = false
            if r.skipped == 0 && !r.limited {
                if let baseline = watchAlertBaseline { if AlertCenter.shared.recordGrowth(root: url, before: baseline, after: r.logical, enabled: features.monitor.alertsEnabled) { watchAlertBaseline = r.logical } } else { watchAlertBaseline = r.logical }
            }
            watchError = r.skipped > 0 || r.limited ? "Some files could not be measured. Growth is an estimate." : nil
            if watchSchedule.finish() { scheduleWatchScan() }
        }
    }
    func stopWatching() { recursiveWatch = nil; watchTimer?.invalidate(); watchTimer = nil; watchTask?.cancel(); watchToken.cancel(); watchGeneration = UUID(); watching = false; watchScanning = false; watchSchedule.clear() }
    /// Removes the current folder from the watchlist. No files are touched.
    func removeWatch() {
        stopWatching()
        watchURL = nil; watchBaseline = nil; watchAlertBaseline = nil
        watchSize = nil; watchEvents = 0; watchChanged = nil; watchError = nil
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
        if watching { watchSchedule.changed(); scheduleWatchScan() }
        if result != nil { scan(force: true, automatic: true) }
        if page == .developer || page == .overview { scanCaches() }
        if page == .findSpace { findSpace() }
        if page == .trash { inspectTrash() }
        if page == .docker { inspectDocker() }
        refreshDirtyVisibleInventory()
    }
}
