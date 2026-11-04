import SwiftUI
import AppKit

struct InventoryList: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
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
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
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
            if roots.isEmpty { EmptyPanel(symbol: "chart.line.uptrend.xyaxis", title: "History starts with your next scan", detail: "Scan the same folder on different days to see what grew or disappeared. Partial scans are excluded; Nuke Sweep cannot reconstruct past weeks.") }
            else {
                Picker("Folder", selection: Binding(get: { selectedRoot }, set: { root = $0; baseline = nil })) { ForEach(roots, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 650)
                Picker("Chart range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30); Text("All scans").tag(0) }.pickerStyle(.segmented).frame(width: 300)
                if chartScans.count >= 2 { GrowthHistoryChart(scans: chartScans) } else { Text("Not enough scans in this chart range.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if let latest = scans.first, let previous {
                    HStack { Text("Latest: \(latest.date.formatted())").font(.system(size: 11)).foregroundStyle(Theme.secondary); Spacer(); Picker("Compare with", selection: Binding(get: { previous.id }, set: { baseline = $0 })) { ForEach(Array(scans.dropFirst())) { Text($0.date.formatted(date: .abbreviated, time: .standard)).tag($0.id) } }.frame(width: 300) }
                    Picker("Group by", selection: $categories) { Text("Folders / files").tag(false); Text("Category").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    let rows = GrowthComparison.rows(before: categories ? previous.categories : previous.sizes, after: categories ? latest.categories : latest.sizes)
                    GrowthChangeChart(rows: rows, inspectedName: $inspectedName)
                    HStack { Text("ITEM"); Spacer(); Text("BEFORE").frame(width: 100, alignment: .trailing); Text("LATEST").frame(width: 100, alignment: .trailing); Text("CHANGE").frame(width: 110, alignment: .trailing) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in HStack { Text(row.name).lineLimit(1).truncationMode(.middle); Spacer(); Text(bytes(row.before)).frame(width: 100, alignment: .trailing); Text(bytes(row.after)).frame(width: 100, alignment: .trailing); Text((row.delta > 0 ? "+" : row.delta < 0 ? "−" : "") + bytes(abs(row.delta))).foregroundStyle(row.delta > 0 ? Theme.orange : Theme.green).frame(width: 110, alignment: .trailing) }.font(.system(size: 12)).monospacedDigit().padding(.vertical, 12).background(inspectedName == row.name ? Theme.orange.opacity(0.08) : .clear); Divider() }
                    }
                    Notice(text: "Categories are inferred from paths and file types. Only the same scanned root is compared. File moves can appear as removal plus growth, and logical bytes are not unique allocated space. The most recent 200 complete scans are retained locally, with up to 500 named items per scan and an aggregate for the remainder.", symbol: "info.circle")
                } else { EmptyPanel(symbol: "clock", title: "One scan saved", detail: "Scan this folder again to compare it with \(scans.first?.date.formatted() ?? "the first measurement").") }
            }
        }
    }
}
struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @State private var onlyNodeModules = false
    @State private var minimumBytes: Int64 = 0
    private var entries: [InventoryEntry] {
        features.projects.flatMap(\.entries).filter { (!onlyNodeModules || $0.item.name == "node_modules") && $0.item.size >= minimumBytes }.sorted { $0.item.size > $1.item.size }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(features.projectRoot?.path ?? "Choose your projects folder. We look for installed dependencies and generated build folders.").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                Spacer()
                Button("Find build folders…") { features.scanProjects() }.buttonStyle(PrimaryButton()).disabled(features.projectLoading)
            }
            if features.projectLoading { BusyLine(text: "Finding and measuring build folders. You can keep using the app; Stop cancels the search.") }
            if !features.projectDiscoveryNote.isEmpty { Text(features.projectDiscoveryNote).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            HStack {
                Toggle("node_modules only", isOn: $onlyNodeModules).toggleStyle(.checkbox)
                Picker("Minimum size", selection: $minimumBytes) {
                    Text("Any size").tag(Int64(0)); Text("100 MB+").tag(Int64(100_000_000)); Text("1 GB+").tag(Int64(1_000_000_000))
                }.frame(width: 180)
                Spacer()
                Text("Largest first").foregroundStyle(Theme.secondary)
            }.font(.system(size: 12))
            InventoryList(entries: entries, measured: features.projectMeasured)
            if !features.projectLoading && features.projectRoot != nil && entries.isEmpty {
                EmptyPanel(symbol: "folder.badge.gearshape", title: "No build folders match", detail: "Try Any size or choose a broader projects folder. Search covers up to 12 levels, 10,000 directories, and 300 workspaces within 90 seconds. Partial coverage is shown above.")
            }
            Notice(text: "These are disk-space candidates, not RAM. Nothing is selected automatically. node_modules can be reinstalled; build/dist folders can also contain hand-edited work. Every selected folder gets a fresh review before moving to Trash.", symbol: "info.circle")
            if !features.projectNote.isEmpty {
                DisclosureGroup("Docker context details") {
                    Text("Context: " + features.projectContext + ". " + features.projectNote).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    ForEach(features.projectDocker) { object in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(object.project + " · " + object.kind + " · " + object.name)
                            Text(object.directory ?? "Working directory not recorded").foregroundStyle(Theme.secondary)
                        }.font(.system(size: 11)).padding(.vertical, 6)
                    }
                    Button("Open Docker management") { model.page = .docker }.buttonStyle(QuietButton())
                }
            }
        }
    }
}
struct AIStorageView: View {
    @EnvironmentObject var features: FeatureModel
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
            ForEach(features.ai.notes, id: \.self) { Notice(text: $0, symbol: "info.circle") }
            if !features.aiLoading && features.ai.entries.isEmpty { EmptyPanel(symbol: "externaldrive", title: features.aiScanned ? "No model folders measured" : "Review downloaded models", detail: "Inspect common locations or add your model folder. No results does not mean there are no models elsewhere. Download cost and active use are unknown.") }
        }
    }
}
struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @State private var deleting: SimulatorDevice?
    @State private var confirmation = ""
    @State private var unavailableOnly = false
    private var simulatorRows: [SimulatorDevice] {
        features.simulators.devices.filter { !unavailableOnly || !$0.available }.sorted { ($0.logicalBytes ?? -1) > ($1.logicalBytes ?? -1) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Preserve recovery data you still need.").font(.system(size: 12)).foregroundStyle(Theme.secondary); Spacer(); Button("Open Xcode") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }.buttonStyle(QuietButton()); Button("Inspect devices & archives") { features.scanDevices() }.buttonStyle(PrimaryButton()).disabled(features.deviceLoading) }
            if features.deviceLoading { BusyLine(text: "Reading emulator inventory and measuring device data… you can stop between file operations; an active tool call may take up to 20 seconds.") }
            InventoryList(entries: features.devices.entries, measured: features.deviceMeasured)
            if let result = features.simulatorActionResult { Notice(text: result, symbol: "info.circle") }
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
            if !features.simulators.note.isEmpty { Notice(text: features.simulators.note, symbol: "iphone") }
            ForEach(features.devices.notes, id: \.self) { Notice(text: $0, symbol: "info.circle") }
            if features.devices.entries.isEmpty && !features.deviceLoading { EmptyPanel(symbol: "iphone", title: "Backups are not caches", detail: "Inspect Xcode archives, MobileSync backups, simulator devices, and installed runtime metadata. Shut-down simulator devices can be deleted through Apple’s simulator manager. Android Quick Boot snapshots can go to Trash. Shared runtimes stay managed by Xcode.") }
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
struct BusyLine: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8) }
}
