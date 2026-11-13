import SwiftUI
import AppKit

struct InventoryList: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    let entries: [InventoryEntry]
    var measured: Date? = nil
    @State private var selected = Set<String>()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !entries.isEmpty {
                if let measured { Text("Inspection completed " + measured.formatted()).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Text("Listed sizes: " + bytes(entries.reduce(0) { $0 + $1.item.size }) + (entries.contains { $0.item.incomplete } ? "+" : "") + " · \(entries.filter { !$0.item.incomplete }.count) of \(entries.count) locations complete · not guaranteed freeable space").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("Select \(entry.item.name)", isOn: Binding(get: { selected.contains(entry.id) }, set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(!entry.removable || entry.item.incomplete || model.actionBusy)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(entry.item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle); Spacer(); Text(bytes(entry.item.size) + (entry.item.incomplete ? "+" : "")).font(.system(size: 12, weight: .medium)).monospacedDigit() }
                            Text(entry.category + " · " + entry.owner).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                            Text(entry.item.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            if entry.item.incomplete { Text("Incomplete · cleanup unavailable").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warning) }
                            DisclosureGroup("Ownership & cleanup details") { Text(entry.explanation).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }.font(.system(size: 11))
                            HStack(spacing: 18) {
                                Button("Reveal in Finder") { model.reveal(entry.item.url) }.buttonStyle(.plain)
                                Button("Check file use") { features.inspectUse(entry.item.url) }.buttonStyle(.plain).disabled(features.useLoading)
                            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).padding(.top, 3)
                        }
                    }.padding(.vertical, 17)
                    Divider()
                }
            }
            if entries.contains(where: \.removable) {
                HStack { Text("\(selected.count) selected · no automatic selections").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer(); Button("Review selected…") { model.reviewTrash(entries.filter { selected.contains($0.id) && $0.removable && !$0.item.incomplete }.map(\.item)) }.buttonStyle(PrimaryButton()).disabled(selected.isEmpty || model.actionBusy) }
            }
        }.onChange(of: entries.map(\.id)) { _, _ in selected = [] }
    }
}
struct GrowthView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @Environment(AISettings.self) var ai
    @State private var growthTarget: AIGrowthTarget?
    @AppStorage("nuke.growthRoot") private var root = ""
    @AppStorage("nuke.growthRange") private var range = 30
    @State private var inspectedName: String?
    @AppStorage("nuke.growthBaseline") private var baselineID = ""
    var baseline: UUID? { get { UUID(uuidString: baselineID) } nonmutating set { baselineID = newValue?.uuidString ?? "" } }
    @AppStorage("nuke.growthCategories") private var categories = false
    var roots: [String] { Array(Set(features.scans.map(\.root))).sorted() }
    var selectedRoot: String { roots.contains(root) ? root : roots.first ?? "" }
    var scans: [StoredScan] { features.scans.filter { $0.root == selectedRoot }.sorted { $0.date > $1.date } }
    var chartScans: [StoredScan] { range == 0 ? scans : scans.filter { $0.date >= Date().addingTimeInterval(-Double(range) * 86400) } }
    var previous: StoredScan? { scans.dropFirst().first(where: { $0.id == baseline }) ?? scans.dropFirst().first }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if features.historyLoading { BusyLine(text: "Loading saved scan history…") }
            HStack { Text("Complete scans are saved automatically.").font(.system(size: 12)).foregroundStyle(Theme.secondary); Spacer(); Button("Scan a folder…") { model.chooseFolder() }.buttonStyle(PrimaryButton()) }
            if roots.isEmpty {
                SuggestedStart(
                    title: "History starts with your next scan",
                    detail: "Scan the same folder on different days to see what grew or disappeared. Partial scans are excluded; Nuke Sweep cannot reconstruct past weeks.",
                    symbol: "chart.line.uptrend.xyaxis",
                    choices: [
                        .init(
                            id: "scan-current",
                            name: "Scan " + model.scanRoot.lastPathComponent,
                            detail: String(localized: "Save a first measurement to compare against later"),
                            symbol: "folder.badge.plus"
                        ) { model.page = .storage; model.scan(force: true) }
                    ]
                )
            }
            else {
                Picker("Folder", selection: Binding(get: { selectedRoot }, set: { root = $0; baseline = nil })) { ForEach(roots, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 650)
                Picker("Chart range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30); Text("All scans").tag(0) }.pickerStyle(.segmented).frame(width: 300)
                if chartScans.count >= 2 { GrowthHistoryChart(scans: chartScans) } else { Text("Not enough scans in this chart range.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if let latest = scans.first, let previous {
                    HStack { Text("Latest: \(latest.date.formatted())").font(.system(size: 11)).foregroundStyle(Theme.secondary); Spacer(); Picker("Compare with", selection: Binding(get: { previous.id }, set: { baseline = $0 })) { ForEach(Array(scans.dropFirst())) { Text($0.date.formatted(date: .abbreviated, time: .standard)).tag($0.id) } }.frame(width: 300) }
                    Picker("Group by", selection: $categories) { Text("Folders / files").tag(false); Text("Category").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    let rows = GrowthComparison.rows(before: categories ? previous.categories : previous.sizes, after: categories ? latest.categories : latest.sizes)
                    HStack {
                        if ai.enabled {
                            Button { growthTarget = AIGrowthTarget(context: AIGrowthContext(before: previous, after: latest, rows: rows, rootName: URL(fileURLWithPath: selectedRoot).lastPathComponent)) } label: { Label("Explain growth", systemImage: "sparkles") }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                                .help("Summarise the two stored scans; nothing is moved or deleted")
                        }
                        Spacer()
                    }
                    GrowthChangeChart(rows: rows, inspectedName: $inspectedName)
                    HStack { Text("ITEM"); Spacer(); Text("BEFORE").frame(width: 100, alignment: .trailing); Text("LATEST").frame(width: 100, alignment: .trailing); Text("CHANGE").frame(width: 110, alignment: .trailing) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack {
                                Text(row.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(bytes(row.before)).frame(width: 100, alignment: .trailing)
                                Text(bytes(row.after)).frame(width: 100, alignment: .trailing)
                                Text((row.delta > 0 ? "+" : row.delta < 0 ? "−" : "") + bytes(abs(row.delta)))
                                    .foregroundStyle(row.delta > 0 ? Theme.orange : Theme.green)
                                    .frame(width: 110, alignment: .trailing)
                            }
                            .font(.system(size: 12)).monospacedDigit().padding(.vertical, 12)
                            .background(inspectedName == row.name ? Theme.orange.opacity(0.08) : .clear)
                            Divider()
                        }
                    }
                    Notice(text: "Categories are inferred from paths and file types. Only the same scanned root is compared. File moves can appear as removal plus growth, and logical bytes are not unique allocated space. The most recent 200 complete scans are retained locally, with up to 500 named items per scan and an aggregate for the remainder.", symbol: "info.circle")
            } else {
                SuggestedStart(
                    title: "One scan saved",
                    detail: "Growth compares two complete measurements of the same folder. Scan it again to produce the second one.",
                    symbol: "clock",
                    choices: [
                        .init(id: "scan-again", name: String(localized: "Scan this folder again"),
                              detail: String(format: String(localized: "Compares against %@"), scans.first?.date.formatted() ?? String(localized: "the first measurement")),
                              symbol: "arrow.clockwise") { model.page = .storage; model.scan(force: true) }
                    ]
                )
            }
            }
        }
        .sheet(item: $growthTarget) { AIGrowthSheet(target: $0) }
    }
}
struct ProjectsView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var onlyNodeModules = false
    @State private var minimumBytes: Int64 = 0
    @State private var activeProcesses: [String: [String]] = [:]
    @State private var suggestions: [CodeFolderDetection.Candidate] = []
    @State private var showingStaleOnly = false
    private var staleSweep: StaleProjects.Sweep {
        StaleProjects.sweep(features.projects, activeRoots: Set(model.projectPortActivity.filter { !$0.value.isEmpty }.keys))
    }
    /// The sweep filters the list rather than selecting anything: the user still
    /// reviews whatever they choose from it.
    private var visibleGroups: [ProjectGroup] {
        showingStaleOnly ? staleSweep.groups : features.projects
    }
    private var entries: [InventoryEntry] {
        features.projects.flatMap(\.entries).filter { (!onlyNodeModules || $0.item.name == "node_modules") && $0.item.size >= minimumBytes }.sorted { $0.item.size > $1.item.size }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(features.projectRoot?.path ?? "Choose your projects folder. We look for installed dependencies and generated build folders.").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                Spacer()
                Button("Find build folders…") { features.scanProjects() }.buttonStyle(PrimaryButton()).disabled(features.projectLoading)
                Button("Check activity") { model.refreshProjectActivity() }.buttonStyle(QuietButton()).disabled(model.processLoading || model.projectActivityLoading)
            }
            if features.projectLoading { BusyLine(text: "Finding and measuring build folders. You can keep using the app; Stop cancels the search.") }
            if !features.projectDiscoveryNote.isEmpty { Text(features.projectDiscoveryNote).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            // Offer the conventional locations instead of asking the person to go
            // find their own code. Suggestions only -- choosing still starts a scan.
            if features.projectRoot == nil && !suggestions.isEmpty && !features.projectLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Found these on this Mac").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    ForEach(suggestions) { candidate in
                        Button {
                            FolderAccess.shared.remember(candidate.url)
                            features.scanProjects(rootOverride: candidate.url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.badge.gearshape").foregroundStyle(Theme.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: candidate.displayPath).font(.system(size: 12, weight: .medium))
                                    Text(verbatim: String(format: String(localized: "%@ inside"), Plural.projects(candidate.projectCount)))
                                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            .padding(12).contentShape(Rectangle())
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan \(candidate.name), \(candidate.projectCount) projects inside")
                    }
                }
            }
            // The answer most people are looking for on this screen, stated before
            // the list they would otherwise have to read to find it.
            if !staleSweep.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 16)).foregroundStyle(Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: String(format: String(localized: "%@ untouched for %lld+ months"), Plural.projects(staleSweep.count), staleSweep.months))
                            .font(.system(size: 13, weight: .medium))
                        Text(verbatim: bytes(staleSweep.bytes) + " of dependencies and build output, nothing running in them")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button(showingStaleOnly ? "Show all projects" : "Show these") { showingStaleOnly.toggle() }
                        .buttonStyle(QuietButton())
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            // Filters describe results, so they appear with them.
            if !features.projects.isEmpty {
                HStack {
                    Toggle("node_modules only", isOn: $onlyNodeModules).toggleStyle(.checkbox)
                    Picker("Minimum size", selection: $minimumBytes) {
                        Text("Any size").tag(Int64(0)); Text("100 MB+").tag(Int64(100_000_000)); Text("1 GB+").tag(Int64(1_000_000_000))
                    }.frame(width: 180)
                    Spacer()
                    Text("Largest first").foregroundStyle(Theme.secondary)
                }.font(.system(size: 12))
            }
            ForEach(visibleGroups) { group in
                let groupEntries = group.entries.filter { (!onlyNodeModules || $0.item.name == "node_modules") && $0.item.size >= minimumBytes }.sorted { $0.item.size > $1.item.size }
                if !groupEntries.isEmpty {
                    let names = Array(Set((activeProcesses[group.id] ?? []) + (model.projectPortActivity[group.id] ?? []))).sorted()
                    ProjectGroupSection(group: group, entries: groupEntries, measured: features.projectMeasured, activeNames: names)
                    Divider()
                }
            }
            if !features.projectLoading && features.projectRoot != nil && entries.isEmpty {
                EmptyPanel(symbol: "folder.badge.gearshape", title: "No build folders match", detail: "Try Any size or choose a broader projects folder. Search covers up to 12 levels, 10,000 directories, and 300 workspaces within 90 seconds. Partial coverage is shown above.")
            }
            Notice(text: "These are disk-space candidates, not RAM. Nothing is selected automatically. node_modules can be reinstalled; build/dist folders can also contain hand-edited work. Every selected folder gets a fresh review before moving to Trash.", symbol: "info.circle")
            if !features.projectNote.isEmpty {
                DisclosureGroup("Docker context details") {
                    Text("Context: \(features.projectContext). \(features.projectNote)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    ForEach(features.projectDocker) { object in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(object.project) · \(object.kind) · \(object.name)")
                            Text(object.directory ?? "Working directory not recorded").foregroundStyle(Theme.secondary)
                        }.font(.system(size: 11)).padding(.vertical, 6)
                    }
                    Button("Open Docker management") { model.page = .docker }.buttonStyle(QuietButton())
                }
            }
        }
        .onAppear { refreshActivity() }
        .onChange(of: model.processes.map(\.pid)) { _, _ in refreshActivity() }
        .onChange(of: features.projects.map(\.id)) { _, _ in refreshActivity(); model.refreshRepositoryState() }
        .onChange(of: model.projectPortActivity) { _, _ in refreshActivity() }
        .task {
            // Reads directories, so it runs on the interactive disk lane rather
            // than blocking the first paint of the screen.
            guard features.projectRoot == nil, suggestions.isEmpty else { return }
            suggestions = await DiskWork.run("Looking for your code", lane: .interactive) {
                CodeFolderDetection.detect()
            }
        }
    }

    private func refreshActivity() {
        activeProcesses = ProjectActivityDetector.active(projects: features.projects, processes: model.processes)
    }
}
private struct ProjectGroupSection: View {
    @Environment(AppModel.self) var model
    let group: ProjectGroup
    let entries: [InventoryEntry]
    let measured: Date?
    let activeNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.root.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(group.kind)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.orange)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
                if !activeNames.isEmpty {
                    Text(ProjectActivityDetector.summary(activeNames))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.green).lineLimit(1)
                        .help("Heuristic: a running command contains this project's absolute path. It may be a build, editor helper or dev server.")
                        .accessibilityLabel("Possibly active processes: " + activeNames.joined(separator: ", "))
                }
                Spacer()
                Text(bytes(group.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
                Button("Reveal") { model.reveal(group.root) }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                    .accessibilityLabel("Reveal \(group.root.lastPathComponent) in Finder")
            }
            Text(group.rebuildGuidance).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            InventoryList(entries: entries, measured: measured)
        }
    }
}

struct AIStorageView: View {
    @Environment(FeatureModel.self) var features
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Ollama, Hugging Face, LM Studio, and your chosen folders").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Add folder…") { features.addModelFolder() }.buttonStyle(QuietButton()).disabled(features.aiLoading)
                Button("Inspect models") { features.scanAI() }.buttonStyle(PrimaryButton()).disabled(features.aiLoading)
            }
            if features.aiLoading { BusyLine(text: "Queued or measuring model folders… cancellation happens between filesystem calls.") }
            InventoryList(entries: features.ai.entries, measured: features.aiMeasured)
            if !features.aiModels.isEmpty {
                DisclosureGroup("Model metadata · \(features.aiModels.count) entries, up to 100") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(features.aiModels) { record in
                            VStack(alignment: .leading, spacing: 4) { Text(record.name).font(.system(size: 12, weight: .medium)); Text(record.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        }
                    }.padding(.top, 12)
                }
                Text("Metadata inspection is bounded. Individual model deletion stays in the owning tool; shared blobs are never selected separately.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if !features.aiCustomPaths.isEmpty {
                DisclosureGroup("Custom locations") {
                    ForEach(features.aiCustomPaths, id: \.self) { path in HStack { Text(path).font(.system(size: 11)).textSelection(.enabled); Spacer(); Button("Remove from list") { features.forgetModelFolder(path) }.disabled(features.aiLoading) } }
                }
            }
            ForEach(features.ai.notes, id: \.self) { Notice.measured($0, symbol: "info.circle") }
            if !features.aiLoading && features.ai.entries.isEmpty {
                SuggestedStart(
                    title: features.aiScanned ? "No model folders measured" : "Review downloaded models",
                    detail: "Local model weights are large and easy to forget. No result here does not mean there are no models elsewhere, and download cost and active use are unknown.",
                    symbol: "externaldrive",
                    choices: []
                )
            }
        }
    }
}
struct DevicesView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var deleting: SimulatorDevice?
    @State private var confirmation = ""
    @State private var unavailableOnly = false
    @State private var showingSimulators = true
    private var simulatorRows: [SimulatorDevice] {
        features.simulators.devices.filter { !unavailableOnly || !$0.available }.sorted { ($0.logicalBytes ?? -1) > ($1.logicalBytes ?? -1) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Preserve recovery data you still need.").font(.system(size: 12)).foregroundStyle(Theme.secondary); Spacer(); Button("Open Xcode") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }.buttonStyle(QuietButton()); Button("Inspect devices & archives") { features.scanDevices() }.buttonStyle(PrimaryButton()).disabled(features.deviceLoading) }
            if features.deviceLoading { BusyLine(text: "Reading emulator inventory and measuring device data… you can stop between file operations; an active tool call may take up to 20 seconds.") }
            Picker("Device storage", selection: $showingSimulators) {
                Text("Simulator devices").tag(true)
                Text("Archives & backups").tag(false)
            }.pickerStyle(.segmented).frame(maxWidth: 380)
            if showingSimulators {
                if simulatorRows.isEmpty && features.simulators.devices.isEmpty && !features.deviceLoading {
                    EmptyPanel(symbol: "iphone", title: "No simulator devices listed",
                               detail: "Inspect devices to check which simulators are installed and how much space they use.")
                }
                if let result = features.simulatorActionResult { Notice.measured(result, symbol: "info.circle") }
                if !features.simulators.devices.isEmpty {
                    HStack {
                        SectionTitle(title: "Simulator devices", detail: "\(features.simulators.devices.count) devices · largest measured folders first")
                        Spacer()
                        Toggle("Unavailable only", isOn: $unavailableOnly).toggleStyle(.checkbox).font(.system(size: 12))
                    }
                    if simulatorRows.isEmpty { Text("No unavailable devices in this inventory.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                }
                ForEach(simulatorRows) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.system(size: 13, weight: .semibold))
                            Text("\(device.runtime) · \(device.state)" + (device.available ? "" : " · unavailable")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(device.logicalBytes.map { bytes($0) + (device.partialMeasurement ? "+ · partial" : " logical") } ?? "Size unavailable").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Button("Delete device…") { confirmation = ""; deleting = device }.buttonStyle(QuietButton()).disabled(!device.canDelete || features.deviceLoading || features.simulatorActionBusy || model.actionBusy)
                    }.padding(12).background(Theme.rail, in: RoundedRectangle(cornerRadius: 8))
                }
                if !features.simulators.note.isEmpty { Notice.measured(features.simulators.note, symbol: "iphone") }
            } else {
                InventoryList(entries: features.devices.entries, measured: features.deviceMeasured)
                ForEach(features.devices.notes, id: \.self) { Notice.measured($0, symbol: "info.circle") }
                if features.devices.entries.isEmpty && !features.deviceLoading {
                    SuggestedStart(
                        title: "Backups are not caches",
                        detail: "Xcode archives, MobileSync backups, simulator devices and installed runtimes. Shut-down simulator devices are deleted through Apple’s simulator manager; Android Quick Boot snapshots can go to Trash; shared runtimes stay managed by Xcode.",
                        symbol: "iphone",
                        choices: []
                    )
                }
            }
        }
        .sheet(item: $deleting) { device in
            VStack(alignment: .leading, spacing: 18) {
                Text("Delete \(device.name)?").font(.title2)
                Text("This permanently removes the simulator’s installed apps and test data. It cannot be restored from Trash. The shared runtime stays installed.")
                Text(device.runtime + " · " + device.state).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Text(device.id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                TextField("Type DELETE to confirm", text: $confirmation).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { deleting = nil }; Spacer()
                    Button("Permanently delete", role: .destructive) { deleting = nil; model.deleteSimulator(device) }.disabled(confirmation != "DELETE")
                }
            }.padding(24).frame(width: 470)
        }
    }
}
/// Takes `LocalizedStringKey` rather than `String` so a literal written at a call
/// site is a translation key, the same way SwiftUI's own `Text` behaves. Use the
/// `verbatim:` initializer for text assembled at runtime, which must not be
/// looked up as a key.
struct BusyLine: View {
    let text: LocalizedStringKey
    init(text: LocalizedStringKey) { self.text = text; self.verbatim = nil }
    /// For progress text that embeds a measured value. A static factory, not an
    /// overloaded init: see SectionTitle.measured.
    static func measured(_ text: String) -> BusyLine {
        var view = BusyLine(text: ""); view.verbatim = text; return view
    }
    private var verbatim: String?
    var body: some View {
        Group { if let verbatim { Text(verbatim: verbatim) } else { Text(text) } }
            .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
    }
}
