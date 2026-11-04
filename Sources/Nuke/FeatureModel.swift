import SwiftUI
import AppKit
import UserNotifications
import WidgetKit
import UniformTypeIdentifiers

@MainActor final class FeatureModel: ObservableObject {
    @Published var scans: [StoredScan] = []
    @Published var receipts: [CleanupReceipt] = []
    @Published var projects: [ProjectGroup] = []
    @Published var projectDocker: [ProjectDockerObject] = []
    @Published var projectContext = ""
    @Published var projectNote = ""
    @Published var projectRoot: URL?
    @Published var projectLoading = false
    @Published var projectMeasured: Date?
    @Published var deviceMeasured: Date?
    @Published var appMeasured: Date?
    @Published var ai = InventoryReport()
    @Published var aiLoading = false
    @Published var aiScanned = false
    @Published var aiMeasured: Date?
    @Published var aiModels: [LocalModelRecord] = []
    @Published var aiCustomPaths = UserDefaults.standard.stringArray(forKey: "nuke.modelRoots") ?? []
    private var aiToken = ScanCancellation()
    private var projectToken = ScanCancellation()
    private var appToken = ScanCancellation()
    @Published var devices = InventoryReport()
    @Published var deviceLoading = false
    @Published var apps: [InstalledApp] = []
    @Published var appLoading = false
    @Published var appNote = ""
    private var startupToken = ScanCancellation()
    @Published var appReport = InventoryReport()
    @Published var selectedApp: InstalledApp?
    @Published var leftovers = InventoryReport()
    @Published var leftoversScanned = false
    @Published var startup: [StartupEntry] = []
    @Published var startupLoading = false
    @Published var startupNote = ""
    @Published var duplicateRoot: URL?
    @Published var duplicates: DuplicateReport?
    @Published var duplicateLoading = false
    @Published var showUse = false
    @Published var useURL: URL?
    @Published var useReport: OpenFileReport?
    @Published var useLoading = false
    @Published var error: String?
    private var storageGeneration = UUID()
    private var dirtyStoragePages = Set<Page>()
    private var historyStarted = false
    @Published var historyLoading = false
    @Published var developerScopes: [DeveloperScope] = {
        guard let data = UserDefaults.standard.data(forKey: "nuke.developerScopes"),
              let saved = try? JSONDecoder().decode([DeveloperScope].self, from: data) else { return [] }
        return saved
    }()
    @Published var scopeMeasurements: [UUID: ScopeMeasurement] = [:]
    @Published var measuringScopes = Set<UUID>()
    @Published var scopeStatus: String?
    private var scopeTokens: [UUID: ScanCancellation] = [:]
    func loadHistory() {
        guard !historyStarted else { return }; historyStarted = true; historyLoading = true
        Task {
            let stored = await DiskWork.run { (LocalStore.load([StoredScan].self, name: "scans.json") ?? [], LocalStore.load([CleanupReceipt].self, name: "receipts.json") ?? []) }
            let existingScans = Set(scans.map(\.id)), existingReceipts = Set(receipts.map(\.id))
            scans = Array((scans + stored.0.filter { !existingScans.contains($0.id) }).sorted { $0.date > $1.date }.prefix(200))
            receipts = Array((receipts + stored.1.filter { !existingReceipts.contains($0.id) }).sorted { $0.date > $1.date }.prefix(200)); historyLoading = false
        }
    }
    let monitor = LiveMonitor()
    var onReceipt: ((CleanupReceipt) -> Void)?
    private var deviceToken = ScanCancellation()
    private var duplicateToken = ScanCancellation()
    func saveScan(root: URL, result: ScanResult) {
        guard result.skipped == 0, !result.limited else { return }
        if let prior = scans.first(where: { $0.root == root.path }) { AlertCenter.shared.recordGrowth(root: root, before: prior.total, after: result.logical, enabled: monitor.alertsEnabled) }
        var sizes = Dictionary(uniqueKeysWithValues: result.items.prefix(500).map { ($0.name, $0.size) })
        if result.items.count > 500 { var key = "Other items (history aggregate)"; while sizes[key] != nil { key += " •" }; sizes[key] = result.items.dropFirst(500).reduce(0) { $0 + $1.size } }
        scans.insert(.init(date: Date(), root: root.path, sizes: sizes, categories: result.categories), at: 0)
        scans = Array(scans.prefix(200))
        FilePersistence.save(scans, name: "scans.json") { [weak self] message in Task { @MainActor in self?.error = "Could not save scan history: " + message } }
    }
    func receipt(_ receipt: CleanupReceipt) {
        onReceipt?(receipt)
        receipts.insert(receipt, at: 0); receipts = Array(receipts.prefix(200))
        FilePersistence.save(receipts, name: "receipts.json") { [weak self] message in Task { @MainActor in self?.error = "Cleanup finished, but its receipt could not be saved: " + message } }
    }
    func invalidateStorageInventories() {
        if aiScanned || aiLoading { dirtyStoragePages.insert(.ai) }
        if projectRoot != nil { dirtyStoragePages.insert(.projects) }
        if appMeasured != nil || appLoading { dirtyStoragePages.insert(.apps) }
        if deviceMeasured != nil || deviceLoading { dirtyStoragePages.insert(.devices) }
        if !startup.isEmpty || startupLoading { dirtyStoragePages.insert(.startup) }
        if duplicateRoot != nil { dirtyStoragePages.insert(.duplicates) }
        storageGeneration = UUID()
        for token in [aiToken, projectToken, appToken, deviceToken, startupToken, duplicateToken] { token.cancel() }
        ai = .init(); aiModels = []; aiScanned = false; aiMeasured = nil; aiLoading = false
        projects = []; projectDocker = []; projectMeasured = nil; projectLoading = false
        apps = []; selectedApp = nil; appReport = .init(); leftovers = .init(); leftoversScanned = false; appMeasured = nil; appLoading = false
        devices = .init(); deviceMeasured = nil; deviceLoading = false
        startup = []; startupLoading = false; duplicates = nil; duplicateLoading = false
    }
    func refreshDirtyStorage(_ page: Page) {
        guard dirtyStoragePages.remove(page) != nil else { return }
        switch page {
        case .ai: scanAI()
        case .projects: if let projectRoot { scanProjects(rootOverride: projectRoot) }
        case .apps: scanApps()
        case .devices: scanDevices()
        case .startup: scanStartup()
        case .duplicates: if let duplicateRoot { findDuplicates(rootOverride: duplicateRoot) }
        default: break
        }
    }
    func folder(_ prompt: String) -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = prompt
        if panel.runModal() == .OK, let url = panel.url { FolderAccess.shared.remember(url); return url }; return nil
    }
    func scanProjects(rootOverride: URL? = nil) {
        guard !projectLoading, let root = rootOverride ?? folder("Inspect projects") else { return }
        projectToken = ScanCancellation(); let token = projectToken
        projectRoot = root; projectLoading = true; projects = []; projectNote = ""
        let generation = storageGeneration
        Task {
            let measured = await DiskWork.run("Inspecting projects", cancellation: token) { InventoryService.projects(root, token: token) }
            guard generation == storageGeneration else { return }; projects = measured
            if token.cancelled { projectNote = "Stopped — partial project inventory."; projectMeasured = Date(); projectLoading = false; return }
            let docker = await Task.detached(priority: .utility) { ProjectDockerService.inspect() }.value
            guard generation == storageGeneration else { return }
            projectDocker = docker.objects; projectContext = docker.context; projectNote = docker.note; projectMeasured = Date(); projectLoading = false
        }
    }
    func cancelProjects() { projectToken.cancel() }
    func addModelFolder() {
        guard !aiLoading, let url = folder("Inspect model folder") else { return }
        if !aiCustomPaths.contains(url.path) { aiCustomPaths.append(url.path); UserDefaults.standard.set(aiCustomPaths, forKey: "nuke.modelRoots") }
        scanAI()
    }
    func forgetModelFolder(_ path: String) {
        aiCustomPaths.removeAll { $0 == path }; UserDefaults.standard.set(aiCustomPaths, forKey: "nuke.modelRoots")
        ai = .init(); aiModels = []; aiScanned = false; aiMeasured = nil
    }
    func cancelAI() { aiToken.cancel() }
    func scanAI() {
        guard !aiLoading else { return }; aiLoading = true; aiToken = ScanCancellation()
        let token = aiToken, custom = aiCustomPaths.map { URL(fileURLWithPath: $0) }
        let generation = storageGeneration
        Task {
            let result = await DiskWork.run("Inspecting local models", cancellation: token) { () -> (InventoryReport, [LocalModelRecord]) in
                let report = InventoryService.ai(custom: custom, token: token)
                let models = LocalModelCatalog.inspect(report.entries, token: token)
                return (report, models)
            }
            guard generation == storageGeneration else { return }
            ai = result.0; aiModels = result.1; aiLoading = false; aiScanned = true; aiMeasured = Date()
        }
    }
    func scanDevices() {
        guard !deviceLoading else { return }; deviceLoading = true
        deviceToken = ScanCancellation(); let token = deviceToken
        let generation = storageGeneration
        Task { let measured = await DiskWork.run("Inspecting devices", cancellation: token) { InventoryService.devices(token: token) }; guard generation == storageGeneration else { return }; devices = measured; deviceMeasured = Date(); deviceLoading = false }
    }
    func cancelDevices() { deviceToken.cancel() }
    func scanApps() {
        guard !appLoading else { return }; appLoading = true; selectedApp = nil; appReport = .init(); leftovers = .init(); leftoversScanned = false
        appToken = ScanCancellation(); let token = appToken; appNote = ""
        let generation = storageGeneration
        Task { let measured = await DiskWork.run("Reading installed apps", cancellation: token) { AppInventory.apps(token: token) }; guard generation == storageGeneration else { return }; apps = measured; appNote = token.cancelled ? "Stopped — partial app inventory." : ""; appMeasured = Date(); appLoading = false }
    }
    func inspectApp(_ app: InstalledApp) {
        guard !appLoading else { return }; appLoading = true; selectedApp = app; appReport = .init(); leftovers = .init(); leftoversScanned = false
        appToken = ScanCancellation(); let token = appToken; appNote = ""
        let generation = storageGeneration
        Task { let measured = await DiskWork.run("Inspecting app files", cancellation: token) { AppInventory.related(app, token: token) }; guard generation == storageGeneration else { return }; appReport = measured; appNote = token.cancelled ? "Stopped — partial app inspection." : ""; appMeasured = Date(); appLoading = false }
    }
    func findLeftovers() {
        guard !appLoading else { return }; appLoading = true; selectedApp = nil; appReport = .init()
        appToken = ScanCancellation(); let token = appToken; appNote = ""
        let generation = storageGeneration
        Task {
            let installed = await DiskWork.run("Reading app identities", cancellation: token) { AppInventory.apps(token: token) }; guard generation == storageGeneration else { return }; apps = installed
            let measured = await DiskWork.run("Inspecting app leftovers", cancellation: token) { AppInventory.leftovers(installed: installed, token: token) }; guard generation == storageGeneration else { return }; leftovers = measured; leftoversScanned = true; appNote = token.cancelled ? "Stopped — partial leftover inspection." : ""; appMeasured = Date(); appLoading = false
        }
    }
    func cancelApps() { appToken.cancel() }
    func cancelStartup() { startupToken.cancel() }
    func scanStartup() {
        guard !startupLoading else { return }; startupLoading = true
        startupToken = ScanCancellation(); let token = startupToken
        let generation = storageGeneration
        Task {
            let result = await DiskWork.run("Inspecting startup items", cancellation: token) { () -> ([StartupEntry], String) in
                let report = StartupService.inspect(token: token)
                var rows = report.entries
                let installed = AppInventory.apps(token: token)
                for app in installed {
                    if token.cancelled { break }
                    let root = app.url.appendingPathComponent("Contents/Library/LoginItems")
                    for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "app" {
                        if token.cancelled { break }
                        let executable = Bundle(url: url)?.executableURL?.path ?? url.path + "/Contents/MacOS/Unknown"
                        rows.append(.init(source: url, label: url.deletingPathExtension().lastPathComponent, executable: executable, owner: "Bundled with \(app.name) (\(app.bundleID))", state: "Registration/enabled state unknown", scope: "Bundled login helper", missing: StartupService.isMissing(executable), canRemove: false))
                    }
                }
                return (rows, report.note)
            }
            guard generation == storageGeneration else { return }
            startup = result.0; startupNote = (token.cancelled ? "Stopped — partial inspection. " : "") + result.1 + " Bundled helpers are candidates, not enabled login items. macOS manages registration in System Settings."
            startupLoading = false
        }
    }
    func findDuplicates(rootOverride: URL? = nil) {
        guard !duplicateLoading, let root = rootOverride ?? folder("Find duplicates") else { return }
        duplicateRoot = root; duplicates = nil; duplicateLoading = true
        duplicateToken = ScanCancellation(); let token = duplicateToken
        let generation = storageGeneration
        Task { let measured = await DiskWork.run("Finding duplicates", cancellation: token) { DuplicateFinder.find(root, token: token) }; guard generation == storageGeneration else { return }; duplicates = measured; duplicateLoading = false }
    }
    func cancelDuplicates() { duplicateToken.cancel() }
    func inspectUse(_ url: URL) {
        guard !useLoading else { return }; showUse = true; useURL = url; useReport = nil; useLoading = true
        Task { useReport = await Task.detached(priority: .utility) { FileUseService.inspect(url) }.value; useLoading = false }
    }
    func saveDeveloperScopes() {
        guard let data = try? JSONEncoder().encode(developerScopes) else { return }
        UserDefaults.standard.set(data, forKey: "nuke.developerScopes")
    }
    func upsertDeveloperScope(_ scope: DeveloperScope) {
        scopeStatus = nil
        scopeTokens[scope.id]?.cancel(); scopeTokens[scope.id] = nil
        measuringScopes.remove(scope.id); scopeMeasurements[scope.id] = nil
        if let index = developerScopes.firstIndex(where: { $0.id == scope.id }) { developerScopes[index] = scope }
        else { developerScopes.append(scope) }
        saveDeveloperScopes()
    }
    func removeDeveloperScope(_ id: UUID) {
        scopeStatus = nil
        scopeTokens[id]?.cancel(); scopeTokens[id] = nil
        measuringScopes.remove(id); scopeMeasurements[id] = nil
        developerScopes.removeAll { $0.id == id }
        saveDeveloperScopes()
    }
    func measureAllDeveloperScopes() {
        for scope in developerScopes { measureDeveloperScope(scope) }
    }
    /// One level of the scope's children, bounded, with the scope's exclusions skipped.
    func measureDeveloperScope(_ scope: DeveloperScope) {
        guard let current = developerScopes.first(where: { $0.id == scope.id }), !measuringScopes.contains(current.id) else { return }
        guard FileManager.default.fileExists(atPath: current.path) else {
            scopeMeasurements[current.id] = ScopeMeasurement(items: [], measured: Date(), limited: false, skipped: 1)
            return
        }
        measuringScopes.insert(current.id)
        let token = ScanCancellation(); scopeTokens[current.id] = token
        Task {
            let result = await DiskWork.run("Inspecting \(current.displayName)", cancellation: token) {
                DiskScanner.scan(current.url, cancellation: token, limit: 60_000, deadline: Date().addingTimeInterval(15), excluding: current.isExcluded)
            }
            guard scopeTokens[current.id] === token else { return }
            scopeTokens[current.id] = nil; measuringScopes.remove(current.id)
            scopeMeasurements[current.id] = ScopeMeasurement(items: result.items, measured: Date(), limited: result.limited, skipped: result.skipped)
        }
    }
    func exportDeveloperScopes() {
        guard !developerScopes.isEmpty else { scopeStatus = "There are no scopes to export."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Nuke Sweep-scopes.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(developerScopes).write(to: url, options: .atomic)
            scopeStatus = "Exported \(developerScopes.count) scope\(developerScopes.count == 1 ? "" : "s") to \(url.lastPathComponent)."
        } catch { scopeStatus = "Scope export failed: " + error.localizedDescription }
    }
    func importDeveloperScopes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try JSONDecoder().decode([DeveloperScope].self, from: Data(contentsOf: url))
            var added = 0, skipped = 0
            for var scope in incoming {
                guard !developerScopes.contains(where: { $0.path == scope.path }) else { skipped += 1; continue }
                if developerScopes.contains(where: { $0.id == scope.id }) { scope.id = UUID() }
                developerScopes.append(scope); added += 1
            }
            saveDeveloperScopes()
            scopeStatus = "Imported \(added) scope\(added == 1 ? "" : "s")." + (skipped > 0 ? " Skipped \(skipped) already present." : "") + " Access is not granted automatically."
        } catch { scopeStatus = "Scope import failed: " + error.localizedDescription }
    }
    func exportAllReceipts() {
        guard !receipts.isEmpty else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Nuke Sweep-receipts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(receipts).write(to: url, options: .atomic)
        } catch { self.error = "Could not export receipts: " + error.localizedDescription }
    }
    func exportReceipt(_ receipt: CleanupReceipt) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Nuke Sweep-receipt-\(receipt.id.uuidString.prefix(8)).json"
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(receipt).write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
}
