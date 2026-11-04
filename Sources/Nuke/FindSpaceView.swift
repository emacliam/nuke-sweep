import SwiftUI
import Darwin

/// The last quick pass is persisted with the workspace so Cleanup opens on evidence,
/// not on a blank page, after the app relaunches.
struct QuickScanState: Codable {
    var busy = false
    var started: Date?
    var measured: Date?
    var step = ""
    var entries: [InventoryEntry] = []
    var notes: [String] = []
    var trashSize: Int64?
    var trashPartial = false

    var stopped: Bool { step.hasPrefix("Stopped") }
    var incomplete: Bool { trashPartial || entries.contains { $0.item.incomplete } }
    var measuredBytes: Int64 { entries.reduce(0) { $0 + $1.item.size } }
}
extension AppModel {
    func findSpace(rootsOverride: [(String, URL)]? = nil, includeTrash: Bool = true) {
        guard !quick.busy else { return }
        quickTokenForScan().cancel()
        let token = newQuickToken()
        quick = QuickScanState(busy: true, started: Date(), step: "Preparing bounded inspection…")
        Task {
            let roots = rootsOverride ?? ([("Application caches", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))])
            var candidates: [String: InventoryEntry] = [:]
            for (index, pair) in roots.enumerated() {
                if token.cancelled { break }
                quick.step = "\(index + 1) of \(roots.count + (includeTrash ? 1 : 0)) · \(pair.0)"
                let measured = await DiskWork.run("Inspecting " + pair.0, cancellation: token) { () -> ScanResult? in
                    var info = stat()
                    if lstat(pair.1.path, &info) != 0 && (errno == ENOENT || errno == ENOTDIR) { return nil }
                    let result = DiskScanner.scan(pair.1, cancellation: token, limit: 12_000, deadline: Date().addingTimeInterval(8))
                    return result
                }
                guard let scan = measured else { continue }
                guard isCurrentQuick(token) else { return }
                if pair.0 == "Application caches" {
                    for item in scan.items { candidates[item.id] = InventoryEntry(item: item, category: "Application caches", owner: item.name + " (inferred)", explanation: "Files accumulated in an app cache location. The owner is inferred from its folder name. The app may need to rebuild or download this data; stop it first.") }
                } else if let rule = CacheRule.all.first(where: { $0.url == pair.1 }), let identity = FileIdentity.read(rule.url) {
                    let item = DiskItem(url: rule.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: nil, identity: identity, incomplete: scan.skipped > 0 || scan.limited)
                    candidates[item.id] = .init(item: item, category: "Developer artifacts", owner: rule.name, explanation: rule.detail)
                }
                if scan.skipped > 0 || scan.limited { quick.notes.append(pair.0 + ": incomplete or unavailable. This quick pass is bounded to 12,000 entries / 8 seconds per location; use a full folder scan before cleanup.") }
                quick.entries = candidates.values.sorted { $0.item.size > $1.item.size }
            }
            if includeTrash && !token.cancelled {
                quick.step = "Inspecting Trash size…"
                let scan = await DiskWork.run("Inspecting Trash", cancellation: token) { DiskScanner.scan(TrashService.current.root, cancellation: token, limit: 12_000, deadline: Date().addingTimeInterval(8)) }
                guard isCurrentQuick(token) else { return }
                quick.trashSize = scan.skipped == 0 && !scan.limited ? scan.logical : nil
                quick.trashPartial = scan.skipped > 0 || scan.limited
            }
            guard isCurrentQuick(token) else { return }
            quick.busy = false; quick.measured = Date(); quick.step = token.cancelled ? "Stopped — partial results" : "Inspection finished"
            scheduleSessionSave()
        }
    }
}
struct FindSpaceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    var selectedEntries: [InventoryEntry] { model.quick.entries.filter { model.quickSelected.contains($0.id) && !$0.item.incomplete } }
    var hasPass: Bool { model.quick.measured != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CleanupStorageSummary()
            if let receipt = features.receipts.first { LastCleanupNote(receipt: receipt) }
            if hasPass { lastPassHeader } else { QuickStartCard() }
            if hasPass {
                categories
                trashSection
                if !model.quick.notes.isEmpty || model.quick.trashPartial {
                    Notice(text: model.quick.notes.joined(separator: "\n") + (model.quick.trashPartial ? "\nTrash could not be inspected completely. It is not empty by inference." : ""), symbol: "info.circle")
                    Button("Resolve access and retry") { model.prepareRecovery(.findSpace) }.buttonStyle(QuietButton())
                }
                if model.quick.entries.isEmpty {
                    EmptyPanel(symbol: "checkmark.circle", title: "No application cache candidates measured", detail: "Nothing was found in ~/Library/Caches within this bounded pass. Developer caches have their own tab. Trash is reported above and is never inferred empty from a denied scan.")
                }
            }
        }
    }
    var lastPassHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Last quick pass " + (model.quick.measured?.formatted(date: .abbreviated, time: .shortened) ?? "just now")).font(.system(size: 12, weight: .medium))
                Text(summary).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if model.quick.stopped { Label("Stopped — partial", systemImage: "pause.circle").font(.system(size: 11)).foregroundStyle(Theme.warning) }
            Button(model.quick.busy ? "Scanning…" : "Scan again") { model.quickSelected = []; model.findSpace() }.buttonStyle(QuietButton()).disabled(model.quick.busy || model.actionBusy)
        }
    }
    var summary: String {
        let total = bytes(model.quick.measuredBytes) + (model.quick.incomplete ? "+" : "")
        let trash = model.quick.trashSize.map(bytes) ?? "not measured"
        return "\(model.quick.entries.count) candidates · \(total) measured · Trash \(trash)"
    }
    @ViewBuilder var categories: some View {
        ForEach(["Developer artifacts", "Application caches"], id: \.self) { category in
            let rows = model.quick.entries.filter { $0.category == category }
            if !rows.isEmpty {
                SectionTitle(title: category, detail: "Review individually · logical size")
                LazyVStack(spacing: 0) {
                    ForEach(rows) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("Select " + entry.item.name, isOn: Binding(get: { model.quickSelected.contains(entry.id) }, set: { if $0 { model.quickSelected.insert(entry.id) } else { model.quickSelected.remove(entry.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(entry.item.incomplete || model.quick.busy || model.actionBusy)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(entry.owner).fontWeight(.semibold); Spacer(); Text(bytes(entry.item.size) + (entry.item.incomplete ? "+" : "")).monospacedDigit() }.font(.system(size: 12))
                                DisclosureGroup("Details and cleanup impact") {
                                    Text(entry.explanation).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    Text(entry.item.url.path).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                                }.font(.system(size: 11))
                                HStack {
                                    Button("Reveal") { model.reveal(entry.item.url) }.buttonStyle(.plain)
                                    Button("Full folder scan") { model.browseTree(entry.item.url) }.buttonStyle(.plain).help("Measure the whole folder and open it as a tree")
                                    Button("Check running use") { features.inspectUse(entry.item.url) }.buttonStyle(.plain).disabled(features.useLoading)
                                }.font(.system(size: 11)).foregroundStyle(Theme.orange)
                                if features.useURL == entry.item.url, let report = features.useReport { Text(report.uses.isEmpty ? "No open uses detected within visibility; this is not proof of inactivity." : "Detected: " + Array(Set(report.uses.map(\.process))).sorted().joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                                if entry.item.incomplete { Text("Incomplete measurement — full scan or access recovery required.").font(.system(size: 11)).foregroundStyle(Theme.warning) }
                            }
                        }.padding(.vertical, 14); Divider()
                    }
                }
            }
        }
    }
    var trashSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Trash", detail: "Permanent deletion has a separate review")
            HStack { Text(model.quick.trashSize.map(bytes) ?? "Size unavailable or not inspected").font(.system(size: 12)); Spacer(); Button("Review Trash separately…") { model.page = .trash; model.inspectTrash() }.buttonStyle(QuietButton()) }
        }
    }
}

/// First-run Cleanup surface: explains exactly what the bounded pass touches and keeps
/// the primary action beside that explanation instead of stranding it at the window edge.
struct QuickStartCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Start with common build-up").font(.system(size: 15, weight: .semibold))
                    Text("A bounded measurement of application caches and Trash. Developer caches stay in their own tab.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    scopeRow("folder", "Application caches", "~/Library/Caches · up to 12,000 entries or 8 seconds per location")
                    Divider()
                    scopeRow("trash", "Trash", "~/.Trash · size only; emptying has its own review")
                    Divider()
                    scopeRow("hammer", "Developer caches", "Xcode, npm, pip, Gradle · measured in the Developer tab") {
                        model.page = .developer
                    }
                }
                HStack(spacing: 12) {
                    Label("Nothing is selected automatically.", systemImage: "checkmark.shield").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(model.quick.busy ? "Scanning…" : "Find space") {
                        model.quickSelected = []
                        model.findSpace()
                    }.buttonStyle(PrimaryButton()).disabled(model.quick.busy || model.actionBusy)
                }
            }
        }
    }
    func scopeRow(_ symbol: String, _ title: String, _ detail: String, go: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let go { Button("Open Developer", action: go).buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange) }
        }.padding(.vertical, 10)
    }
}

/// Isolated from the scan model so monitor ticks only update this small summary.
struct CleanupStorageSummary: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var monitor: LiveMonitor
    private var disk: ResourceSnapshot { monitor.monitorEnabled && !monitor.monitorPaused ? monitor.sample?.disk ?? model.resources : model.resources }
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.system(size: 15)).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Macintosh storage").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text(disk.totalDisk > 0 ? bytes(disk.freeDisk) + " available" : "Storage reading unavailable").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            if disk.totalDisk > 0 {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.orange).frame(width: max(0, (geo.size.width - 3) * disk.diskFraction))
                        RoundedRectangle(cornerRadius: 3).fill(Theme.rail)
                    }
                }.frame(width: 170, height: 8)
                    .accessibilityLabel("\(bytes(disk.usedDisk)) used of \(bytes(disk.totalDisk))")
                Text("of " + bytes(disk.totalDisk)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            Button { model.refreshResources() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }.buttonStyle(.plain).help("Refresh storage reading")
        }.padding(.vertical, 4)
    }
}
