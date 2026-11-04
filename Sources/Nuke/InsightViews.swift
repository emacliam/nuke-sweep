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
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(features.projectRoot?.path ?? "Choose a project or workspace folder.").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2); Spacer(); Button("Inspect workspace…") { features.scanProjects() }.buttonStyle(PrimaryButton()).disabled(features.projectLoading) }
            if features.projectLoading { BusyLine(text: "Finding project artifacts… an in-flight Docker command may take a moment to finish.") }
            ForEach(features.projects) { project in
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: project.root.lastPathComponent, detail: project.kind + " · " + bytes(project.size) + (project.entries.contains { $0.item.incomplete } ? "+" : ""))
                    Text(project.root.path).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    if project.entries.isEmpty { Text("No known artifact folders found.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                    InventoryList(entries: project.entries, measured: features.projectMeasured)
                    let containers = features.projectDocker.filter { $0.directory.map { URL(fileURLWithPath: $0).standardizedFileURL.path == project.root.standardizedFileURL.path } == true }
                    let names = Set(containers.map(\.project))
                    let objects = features.projectDocker.filter { names.contains($0.project) }
                    ForEach(objects) { object in HStack { Label(object.name, systemImage: "shippingbox"); Spacer(); Text(object.kind + " · " + object.state) }.font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                }.padding(.vertical, 8)
            }
            if !features.projectLoading && features.projectRoot != nil && features.projects.isEmpty { EmptyPanel(symbol: "folder.badge.gearshape", title: "No recognized projects found", detail: "Search covers three folder levels, up to 500 folders and 40 projects. It looks for package.json, Cargo.toml, Package.swift, Xcode projects, Python, Gradle, and Go markers.") }
            if !features.projectNote.isEmpty { Notice(text: "Docker context: \(features.projectContext.isEmpty ? "unavailable" : features.projectContext). " + features.projectNote, symbol: "info.circle") }
            if !features.projectDocker.isEmpty {
                DisclosureGroup("All labelled Docker resources (including unassigned folders)") { ForEach(features.projectDocker) { object in VStack(alignment: .leading, spacing: 4) { Text(object.project + " · " + object.kind + " · " + object.name); Text(object.directory ?? "Working directory not recorded").foregroundStyle(Theme.secondary) }.font(.system(size: 11)).padding(.vertical, 6) } }
                Button("Open Docker management") { model.page = .docker }.buttonStyle(QuietButton())
            }
            Notice(text: "Project cleanup covers known artifact locations, not arbitrary source deletion. Discovery is bounded to three levels/500 folders/40 projects; nested workspaces may require a separate scan. Inspect name-based candidates and stop builds first. Docker volumes are shown for context, never selected for automatic deletion.", symbol: "info.circle")
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
    @EnvironmentObject var features: FeatureModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Preserve recovery data you still need.").font(.system(size: 12)).foregroundStyle(Theme.secondary); Spacer(); Button("Open Xcode") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }.buttonStyle(QuietButton()); Button("Inspect devices & archives") { features.scanDevices() }.buttonStyle(PrimaryButton()).disabled(features.deviceLoading) }
            if features.deviceLoading { BusyLine(text: "Reading simulator inventory and measuring device data… cancellation happens between file operations; a CLI call may take up to 20 seconds.") }
            InventoryList(entries: features.devices.entries, measured: features.deviceMeasured)
            ForEach(features.devices.notes, id: \.self) { Notice(text: $0, symbol: "info.circle") }
            if features.devices.entries.isEmpty && !features.deviceLoading { EmptyPanel(symbol: "iphone", title: "Backups are not caches", detail: "Inspect Xcode archives, MobileSync backups, simulator devices, and installed runtime metadata. Simulator devices and runtimes are managed through Xcode rather than direct directory deletion.") }
        }
    }
}
struct BusyLine: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8) }
}
