import SwiftUI
import NukeWidgetUI
import AppKit

enum Theme {
    static let ink = Color(red: 0.15, green: 0.17, blue: 0.17)
    static let secondary = Color(red: 0.40, green: 0.42, blue: 0.42)
    static let orange = Color(red: 0.76, green: 0.27, blue: 0.13)
    static let paper = Color(red: 0.985, green: 0.981, blue: 0.969)
    static let rail = Color(red: 0.95, green: 0.946, blue: 0.926)
    static let line = Color(red: 0.88, green: 0.88, blue: 0.85)
    static let green = Color(red: 0.22, green: 0.40, blue: 0.33)
    /// Amber is reserved for warnings and attention states so rust stays interaction and brand.
    static let warning = Color(red: 0.65, green: 0.38, blue: 0.04)
    /// Native-feeling error red for failed outcomes; rust stays interaction and brand.
    static let error = Color(red: 0.72, green: 0.16, blue: 0.13)
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(.white).background(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 7)).opacity(isEnabled ? 1 : 0.4)
    }
}
struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(Theme.ink).background(configuration.isPressed ? Theme.line : .white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1)).opacity(isEnabled ? 1 : 0.4)
    }
}
struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                if showsTopbar { topbar; Divider().overlay(Theme.line) }
                sectionBar
                if model.reviewPreparing { HStack { BusyLine(text: "Preparing cleanup review…"); Spacer(); Button("Cancel review") { model.cancelReview() }.buttonStyle(QuietButton()) }.padding(.horizontal, 24).padding(.vertical, 10) }
                DiskQueueNotice()
                if model.page == .storage {
                    if model.mainWindowVisible { StorageView().padding(24) } else { Spacer() }
                } else if model.page == .apps {
                    if model.mainWindowVisible { ApplicationsView().padding(24) } else { Spacer() }
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pageHeading
                        if model.mainWindowVisible {
                        switch model.page {
                        case .findSpace: FindSpaceView()
                        case .alerts: AlertsView()
                        case .permissions: PermissionsView()
                        case .widgets: WidgetsView()
                        case .growth: GrowthView()
                        case .projects: ProjectsView()
                        case .apps: ApplicationsView()
                        case .startup: StartupView()
                        case .duplicates: DuplicatesView()
                        case .ai: AIStorageView()
                        case .devices: DevicesView()
                        case .monitor: MonitorSettingsView()
                        case .overview: OverviewView()
                        case .storage: StorageView()
                        case .developer: DeveloperView()
                        case .trash: TrashCleanupView()
                        case .docker: DockerView()
                        case .processes: ProcessesView()
                        case .watchlist: WatchlistView()
                        case .history: ReceiptsView()
                        }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.id(model.page)
                }
                if model.page == .findSpace && !model.quickSelectedItems.isEmpty {
                    HStack { Text("\(model.quickSelectedItems.count) selected · \(bytes(model.quickSelectedItems.reduce(0) { $0 + $1.size }))").font(.system(size: 12)); Spacer(); Button("Review selected…") { model.reviewTrash(model.quickSelectedItems) }.buttonStyle(PrimaryButton()).disabled(model.quick.busy || model.actionBusy) }.padding(14).background(.white).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Theme.paper)
        }.foregroundStyle(Theme.ink).tint(Theme.orange)
        .sheet(isPresented: $model.showTrashReview) { TrashReview() }
        .sheet(isPresented: $features.showUse) { FileUseView() }
        .task {
            model.openMainWindow = { openWindow(id: "main") }
            model.startServices()
            if ProcessInfo.processInfo.arguments.contains("--capture"),
               let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--capture-page"),
               index + 1 < ProcessInfo.processInfo.arguments.count,
               let page = Page(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
                model.page = page
            }
        }
        .sheet(item: $model.finishedReceipt) { ReceiptFinishView(receipt: $0) }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "nuke" else { return }
            if url.host == "storage" { model.page = .storage }
            if url.host == "monitor" { model.page = .monitor }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: [features.projectLoading, features.appLoading, features.startupLoading, features.duplicateLoading, features.aiLoading, features.deviceLoading, model.scanning]) { _, _ in
            if ProcessInfo.processInfo.arguments.contains("--capture") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { AppDelegate.capture(name: model.page.rawValue.lowercased()) }
            }
        }

        .alert("Nuke Sweep", isPresented: Binding(get: { model.message != nil || features.error != nil }, set: { if !$0 { model.message = nil; features.error = nil } })) { Button("Done") { model.message = nil; features.error = nil }; if model.recovery != nil { Button("Review access and retry") { model.message = nil; features.error = nil; model.page = .permissions } } } message: { Text(model.message ?? features.error ?? "") }
        .onChange(of: model.page) { _, newPage in
            if ProcessInfo.processInfo.arguments.contains("--capture") { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { AppDelegate.capture(name: newPage.rawValue.lowercased()) } }
            if newPage == .trash && model.trashSnapshot == nil { model.inspectTrash() }
            if newPage == .processes { model.refreshProcesses() }
            if newPage == .docker { model.inspectDocker() }
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SweepMark().frame(width: 31, height: 28)
                Text("Nuke Sweep").font(.system(size: 18, weight: .semibold)).tracking(-0.4).lineLimit(1)
            }.padding(.top, 28).padding(.bottom, 20).padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 6) {
                coreNav("Cleanup", icon: "sparkle.magnifyingglass", section: .cleanup, destination: .findSpace)
                coreNav("Files", icon: "folder", section: .files, destination: .storage)
                coreNav("Apps", icon: "app.badge", section: .apps, destination: .apps)
                coreNav("History", icon: "clock.arrow.circlepath", section: .history, destination: .history)
            }.padding(.horizontal, 12)
            Spacer(minLength: 12)
            coreNav("Settings", icon: "gearshape", section: .settings, destination: .monitor).padding(.horizontal, 12).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) { Circle().fill(Theme.green).frame(width: 6, height: 6); Text("On this Mac").font(.system(size: 11, weight: .medium)) }
                HStack(spacing: 9) { Image(systemName: "laptopcomputer").font(.system(size: 15)); VStack(alignment: .leading, spacing: 2) { Text(Host.current().localizedName ?? "This Mac").font(.system(size: 11, weight: .semibold)).lineLimit(1); Text("\(bytes(model.resources.physicalMemory)) memory").font(.system(size: 10)).foregroundStyle(Theme.secondary) } }
                Text("Nuke Sweep 0.8.1").font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 16)
        }.frame(width: 202).background(Theme.rail)
    }
    func coreNav(_ title: String, icon: String, section: NavigationSection, destination: Page) -> some View {
        Button { model.page = destination } label: {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 19); Text(title); Spacer() }
                .font(.system(size: 13, weight: model.page.section == section ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(model.page.section == section ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(model.page.section == section ? .isSelected : [])
    }
    @ViewBuilder var sectionBar: some View {
        let pages: [Page] = model.page.section == .cleanup ? [.findSpace, .developer, .trash] : model.page.section == .files ? [.storage, .duplicates, .growth, .watchlist] : model.page.section == .settings ? [.monitor, .permissions, .alerts, .widgets, .startup, .processes] : []
        if !pages.isEmpty {
            HStack(spacing: 18) {
                ForEach(pages) { page in
                    let selected = isCurrentSection(page)
                    Button(tabTitle(page)) { model.page = page == .developer ? .developer : page }
                        .buttonStyle(.plain).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.orange : Theme.secondary)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { if selected { Rectangle().fill(Theme.orange).frame(height: 2) } }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).background(Theme.paper)
        }
    }
    func tabTitle(_ page: Page) -> String {
        if page == .findSpace { return "Quick scan" }
        return page.sidebarTitle
    }
    func isCurrentSection(_ tab: Page) -> Bool {
        if tab == .developer { return [.developer, .projects, .docker, .devices, .ai].contains(model.page) }
        return model.page == tab
    }
    /// Pages that live inside a tab get a real back control instead of a static breadcrumb.
    var deepPageParent: Page? {
        switch model.page {
        case .projects, .docker, .devices, .ai: return .developer
        default: return nil
        }
    }
    var showsTopbar: Bool { deepPageParent != nil || model.page == .storage || model.page == .processes }
    var topbar: some View {
        HStack(spacing: 12) {
            if let parent = deepPageParent {
                Button { model.page = parent } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold)); Text(parent == .developer ? "Developer" : parent.sidebarTitle) }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }.buttonStyle(.plain).help("Back to \(parent == .developer ? "Developer" : parent.sidebarTitle)")
            }
            Spacer()
            if model.page == .storage || model.page == .processes {
                HStack { Image(systemName: "magnifyingglass"); TextField("Filter \(model.page == .storage ? "files" : "processes")", text: $model.search).textFieldStyle(.plain).focused($searchFocused) }.font(.system(size: 11)).padding(8).frame(width: 185).background(.white, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            }
            Button { model.refreshResources() } label: { Image(systemName: "arrow.clockwise").padding(7) }.buttonStyle(.plain).help("Refresh Mac storage and load")
        }.padding(.horizontal, 24).frame(height: 40)
            .onChange(of: model.focusFilterRequest) { _, _ in searchFocused = true }
    }
    var pageHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.page == .findSpace ? "Cleanup" : model.page.sidebarTitle).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
                Text(model.page.subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
struct SectionTitle: View {
    let title: String
    var detail: String = ""
    var body: some View { HStack { Text(title).font(.system(size: 15, weight: .semibold)); Spacer(); Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondary) } }
}
struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)) }
}
struct StorageMeter: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var monitor: LiveMonitor
    private var disk: ResourceSnapshot { monitor.monitorEnabled && !monitor.monitorPaused ? (monitor.sample?.disk ?? model.resources) : model.resources }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Macintosh storage", systemImage: "internaldrive").font(.system(size: 13, weight: .semibold))
                Spacer(); Text(disk.totalDisk > 0 ? "\(bytes(disk.freeDisk)) available" : "Awaiting storage reading").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.green)
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.orange).frame(width: max(0, (geo.size.width - 3) * disk.diskFraction))
                    RoundedRectangle(cornerRadius: 4).fill(Theme.rail)
                }
            }.frame(height: 22).accessibilityLabel(disk.totalDisk > 0 ? "\(bytes(disk.usedDisk)) used of \(bytes(disk.totalDisk))" : "Storage capacity unavailable")
            HStack {
                HStack(spacing: 7) { Circle().fill(Theme.orange).frame(width: 6, height: 6); Text(disk.totalDisk > 0 ? "\(bytes(disk.usedDisk)) used" : "Capacity unavailable") }
                Spacer(); Text(disk.totalDisk > 0 ? "\(bytes(disk.totalDisk)) capacity" : "")
            }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if let error = disk.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.task {
            while !Task.isCancelled {
                if !monitor.monitorEnabled || monitor.monitorPaused { model.refreshResources() }
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }
}
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Surface { StorageMeter() }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 17) {
                    SectionTitle(title: "A good place to start")
                    actionRow("Explore your storage", detail: "Find the folders taking up space.", symbol: "folder", color: Theme.orange) { model.page = .storage }
                    Divider()
                    actionRow("Clear the build-up", detail: "Review developer caches and build artifacts.", symbol: "hammer", color: Theme.green) { model.page = .developer; if model.caches.isEmpty { model.scanCaches() } }
                    Divider()
                    actionRow("See what’s running", detail: "CPU, memory, and processes in one place.", symbol: "waveform.path.ecg", color: Color(red: 0.35, green: 0.38, blue: 0.58)) { model.page = .processes }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 17) {
                    SectionTitle(title: "Developer workspace")
                    VStack(spacing: 0) {
                        ForEach(CacheRule.all) { rule in
                            HStack(spacing: 10) { Image(systemName: rule.symbol).frame(width: 18).foregroundStyle(Theme.secondary); Text(rule.name).font(.system(size: 11)); Spacer(); Text(cacheLabel(rule)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondary) }.padding(.vertical, 12)
                            if rule.id != CacheRule.all.last?.id { Divider() }
                        }
                    }
                    Button { model.page = .developer; model.scanCaches() } label: { HStack { Text(model.cacheScanning ? "Measuring…" : "Review developer storage"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange).disabled(model.cacheScanning)
                }.padding(20).background(Theme.rail.opacity(0.7), in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity)
            }
            Divider()
            HStack(alignment: .top, spacing: 25) {
                Image(systemName: "eye").font(.system(size: 21)).foregroundStyle(Theme.green).padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) { Text("Catch the growth before the cleanup.").font(.system(size: 14, weight: .semibold)); Text("Watch a folder and see how its size changes while you work.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                Spacer(); Button("Set up a watch") { model.page = .watchlist; model.chooseFolder(forWatch: true) }.buttonStyle(QuietButton())
            }
            HStack(spacing: 7) { Image(systemName: "hand.raised"); Text("You choose what goes. Every cleanup starts with a review.") }.font(.system(size: 10)).foregroundStyle(Theme.secondary).padding(.top, 3)
        }
    }
    func cacheLabel(_ rule: CacheRule) -> String { guard let m = model.caches.first(where: { $0.id == rule.id }) else { return "Not scanned" }; return m.item.map { bytes($0.size) + ($0.incomplete ? "+ · partial" : "") } ?? "Not found" }
    func actionRow(_ title: String, detail: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(color).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @AppStorage("nuke.showTreemap") private var showTreemap = false
    @AppStorage("nuke.filesViewMode") private var useTree = false
    @StateObject private var tree = FolderTreeStore()
    @State private var treeSelection: [String: DiskItem] = [:]
    var activeItems: [DiskItem] { useTree ? treeSelection.values.sorted { $0.size > $1.size } : model.selectedItems }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button { let parent = model.scanRoot.deletingLastPathComponent(); model.scan(parent) } label: { Image(systemName: "arrow.up") }.buttonStyle(QuietButton()).help("Scan parent folder").disabled(model.scanning)
                Image(systemName: "folder").foregroundStyle(Theme.orange)
                Text(model.scanRoot.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose folder…") { model.chooseFolder() }.buttonStyle(QuietButton())
                Button("Full scan") { model.scan(force: true) }.buttonStyle(QuietButton()).disabled(model.scanning)
                Button("Refresh folder") { model.scan() }.buttonStyle(PrimaryButton()).disabled(model.scanning)
            }
            if let result = model.result {
                if !model.scanning {
                    HStack(spacing: 6) {
                        if model.scanState.hasPrefix("Stopped") || model.scanState.contains("partial") || model.scanState.contains("incomplete") {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Theme.warning)
                        }
                        Text(model.scanState + (model.resultMeasured.map { " · " + $0.formatted() } ?? "")).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                }
                HStack(spacing: 20) {
                    Text("\(bytes(result.logical))\(result.limited || result.skipped > 0 ? "+" : "") logical size").fontWeight(.semibold)
                    Text("\(result.items.count) items")
                    Spacer()
                    Text("Largest first").foregroundStyle(Theme.secondary)
                    Picker("Files view", selection: $useTree) { Text("Table").tag(false); Text("Tree").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 128)
                        .help("Table lists one level; Tree expands folders in place. Typing a search returns to Table.")
                }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if result.skipped > 0 || result.limited { Notice(text: (model.scanState.hasPrefix("Stopped") ? "Stopped — partial results. Scan again to finish." : result.limited ? "Scan limit reached — partial results. Scan a smaller folder." : "Access incomplete — \(result.skipped) unreadable or skipped locations. Resolve access and retry.") + " Totals may be incomplete.", symbol: "exclamationmark.triangle") }
                if result.skipped > 0 {
                    ForEach(Array(result.accessIssues.prefix(3).enumerated()), id: \.offset) { _, issue in Text(issue.path + ": " + issue.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                    AccessRecovery()
                }
                Text(model.storageIsLive ? "Automatic updates on · folder changes trigger a fresh measurement" : "Periodic refresh when visible · filesystem events unavailable").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                DisclosureGroup("Storage map", isExpanded: $showTreemap) { StorageTreemap(items: result.items) }.font(.system(size: 12))
                if useTree {
                    FolderTreeView(store: tree, selection: $treeSelection, items: result.items)
                } else {
                    fileTable
                }
                HStack { Text("\(bytes(result.allocated))\(result.limited || result.skipped > 0 ? "+" : "") allocated · APFS sharing and hard links can affect totals. Trash does not immediately free space.").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer() }
                HStack(spacing: 8) {
                    Text("\(activeItems.count) selected").font(.system(size: 11))
                    if useTree && !activeItems.isEmpty { Text("· folders move with their contents").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    Spacer()
                    Button("Review selected…") { model.reviewTrash(activeItems) }.buttonStyle(PrimaryButton()).disabled(activeItems.isEmpty || model.actionBusy || model.scanning)
                }
            } else if !model.scanning {
                EmptyPanel(symbol: "folder.badge.magnifyingglass", title: "Start with a folder", detail: "Scan Downloads, a project, or any folder you’d like to understand. Hidden items are included; symbolic links are not followed.")
                HStack { ForEach(["Downloads", "Documents", "Desktop"], id: \.self) { name in Button(name) { model.scan(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)) }.buttonStyle(QuietButton()) } }
            }
        }
        .onChange(of: model.treeResetToken) { _, _ in tree.reset(); treeSelection = [:] }
        .onChange(of: model.scanRoot) { _, _ in tree.reset(); treeSelection = [:] }
        .onChange(of: model.finishedReceipt?.id) { _, _ in tree.reset(); treeSelection = [:] }
        .onChange(of: useTree) { _, isTree in if isTree { model.search = "" } }
        .onChange(of: model.search) { _, text in if !text.isEmpty && useTree { useTree = false } }
    }
    var fileTable: some View {
        Table(model.visibleItems) {
            TableColumn("") { item in
                Toggle("Select \(item.name)", isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }))
                    .labelsHidden().toggleStyle(.checkbox).disabled(item.incomplete || model.actionBusy || model.scanning)
            }.width(24)
            TableColumn("Name") { item in
                HStack(spacing: 8) {
                    Image(systemName: item.symlink ? "link" : item.directory ? "folder.fill" : "doc").foregroundStyle(item.directory ? Theme.orange : Theme.secondary)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.incomplete { Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning).help("Incomplete measurement") }
                }.font(.system(size: 12))
            }
            TableColumn("Logical size") { item in Text(bytes(item.size) + (item.incomplete ? "+" : "")).monospacedDigit().font(.system(size: 11)) }.width(110)
            TableColumn("Actions") { item in
                Menu {
                    Button("Check running use") { features.inspectUse(item.url) }.disabled(features.useLoading)
                    Button("Reveal in Finder") { model.reveal(item.url) }
                    Divider()
                    Button("Scan inside folder") { model.scan(item.url) }.disabled(!item.directory || item.symlink || model.scanning)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 22, height: 20).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Actions for \(item.name)")
                .accessibilityLabel("Actions for \(item.name)")
            }.width(64)
        }.frame(minHeight: 120, maxHeight: .infinity)
            .overlay { if model.visibleItems.isEmpty { Text(model.search.isEmpty ? "No items measured in this folder." : "No items match this filter.").font(.system(size: 12)).foregroundStyle(Theme.secondary) } }
    }
}

struct DeveloperView: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if !model.cacheScanning {
                    HStack(spacing: 6) {
                        if model.cacheOutcome.hasPrefix("Stopped") || model.cacheOutcome.contains("partial") || model.cacheOutcome.contains("gaps") {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Theme.warning)
                        }
                        Text(model.cacheOutcome).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                }
                Spacer()
                Button(model.cacheScanning ? "Scanning…" : model.cacheOutcome == "Not scanned" ? "Scan developer caches" : "Scan again") { model.scanCaches() }.buttonStyle(PrimaryButton()).disabled(model.cacheScanning)
            }
            HStack(spacing: 12) {
                Button("Projects") { model.page = .projects }.buttonStyle(QuietButton())
                Button("Docker") { model.page = .docker }.buttonStyle(QuietButton())
                Button("Devices & Xcode") { model.page = .devices }.buttonStyle(QuietButton())
                if !model.features.ai.entries.isEmpty || !model.features.aiCustomPaths.isEmpty { Button("Local models") { model.page = .ai }.buttonStyle(QuietButton()) }
                Menu("More") { Button("Inspect local models") { model.page = .ai; model.features.scanAI() } }
            }
            VStack(spacing: 0) {
                ForEach(Array(CacheRule.all.prefix(4))) { rule in cacheRow(rule) }
                if CacheRule.all.count > 4 {
                    DisclosureGroup("More built-in caches (\(CacheRule.all.count - 4))") {
                        ForEach(Array(CacheRule.all.dropFirst(4))) { rule in cacheRow(rule) }
                    }.font(.system(size: 12)).padding(.vertical, 4)
                }
            }
            Text("Expand a location for its path, cleanup impact and review action. Nothing is selected automatically.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Divider().padding(.vertical, 6)
            DeveloperScopesSection()
        }
    }

    @ViewBuilder private func cacheRow(_ rule: CacheRule) -> some View {
        let measurement = model.caches.first { $0.id == rule.id }
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded = expanded == rule.id ? nil : rule.id } label: {
                HStack(spacing: 12) {
                    Image(systemName: rule.symbol).foregroundStyle(Theme.orange).frame(width: 22)
                    Text(rule.name).fontWeight(.medium)
                    Spacer()
                    Text(measurement.map { $0.item.map { bytes($0.size) + ($0.incomplete ? "+ · partial" : "") } ?? "Not found" } ?? (model.cacheOutcome.hasPrefix("Stopped") ? "Not inspected" : "Not scanned")).monospacedDigit().foregroundStyle(Theme.secondary)
                    Image(systemName: expanded == rule.id ? "chevron.down" : "chevron.right").font(.system(size: 10)).frame(width: 12)
                }.font(.system(size: 12)).padding(.vertical, 16).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(rule.name + ", " + (expanded == rule.id ? "hide details" : "show details"))
            if expanded == rule.id {
                VStack(alignment: .leading, spacing: 10) {
                    Text("~/" + rule.relativePath).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Text(rule.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if let item = measurement?.item {
                        if item.incomplete { Text(model.cacheOutcome.hasPrefix("Stopped") ? "Stopped while inspecting this location. Browse smaller folders or scan again before cleanup." : (measurement?.skipped ?? 0) > 0 ? "Access incomplete. Resolve folder permissions and scan again before cleanup." : "Scan limit reached. Browse smaller folders to review cleanup.").font(.system(size: 11)).foregroundStyle(Theme.warning) }
                        if (measurement?.skipped ?? 0) > 0 { Button("Review folder access") { model.page = .permissions }.buttonStyle(QuietButton()) }
                        HStack { Button("Browse tree") { model.browseTree(item.url) }.buttonStyle(QuietButton()); Spacer(); Button("Review cleanup…") { model.reviewTrash([item]) }.buttonStyle(PrimaryButton()).disabled(model.actionBusy || model.cacheScanning || item.incomplete || item.size == 0) }
                    }
                }.padding(.leading, 34).padding(.bottom, 16)
            }
            Divider()
        }
    }
}

struct DiskQueueNotice: View {
    @ObservedObject private var activity = DiskActivity.shared
    var body: some View {
        if !activity.running.isEmpty {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(activity.running).fontWeight(.medium); if activity.waiting > 0 { Text("· \(activity.waiting) queued") }; if let started = activity.started { Text(started, style: .relative).monospacedDigit() } }
                    if !activity.path.isEmpty { Text("\(activity.visited) entries · " + activity.path).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.secondary) }
                }.font(.system(size: 11))
                Spacer()
                if activity.canStop { Button("Stop") { activity.stop() }.buttonStyle(QuietButton()) }
            }.padding(.horizontal, 24).padding(.vertical, 10)
                .background(Theme.rail.opacity(0.78))
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .contain)
        }
    }
}

extension Page {
    var sidebarTitle: String { self == .developer ? "Developer" : self == .monitor ? "Menu bar" : self == .storage ? "Browse" : rawValue }
}

enum NavigationSection {
    case cleanup, files, apps, history, settings
    var title: String { switch self { case .cleanup: return "Cleanup"; case .files: return "Files"; case .apps: return "Apps"; case .history: return "History"; case .settings: return "Settings" } }
}
extension Page {
    var section: NavigationSection {
        switch self {
        case .overview, .findSpace, .developer, .trash, .projects, .docker, .ai, .devices: return .cleanup
        case .storage, .growth, .duplicates, .watchlist: return .files
        case .apps: return .apps
        case .history: return .history
        default: return .settings
        }
    }
}
