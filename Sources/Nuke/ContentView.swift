import SwiftUI
import NukeWidgetUI
import AppKit

enum Theme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static let rust = NSColor(red: 0.76, green: 0.27, blue: 0.13, alpha: 1)
    private static let coral = NSColor(red: 0.94, green: 0.47, blue: 0.32, alpha: 1)
    private static let forest = NSColor(red: 0.22, green: 0.40, blue: 0.33, alpha: 1)
    private static let mint = NSColor(red: 0.48, green: 0.78, blue: 0.63, alpha: 1)
    private static let amber = NSColor(red: 0.65, green: 0.38, blue: 0.04, alpha: 1)
    private static let gold = NSColor(red: 0.96, green: 0.68, blue: 0.28, alpha: 1)
    private static let red = NSColor(red: 0.72, green: 0.16, blue: 0.13, alpha: 1)
    private static let salmon = NSColor(red: 0.98, green: 0.47, blue: 0.42, alpha: 1)

    static let ink = adaptive(light: NSColor(red: 0.15, green: 0.17, blue: 0.17, alpha: 1), dark: .labelColor)
    static let secondary = adaptive(light: NSColor(red: 0.40, green: 0.42, blue: 0.42, alpha: 1), dark: .secondaryLabelColor)
    static let orange = adaptive(light: rust, dark: coral)
    static let paper = adaptive(light: NSColor(red: 0.985, green: 0.981, blue: 0.969, alpha: 1), dark: NSColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1))
    static let rail = adaptive(light: NSColor(red: 0.95, green: 0.946, blue: 0.926, alpha: 1), dark: NSColor(red: 0.16, green: 0.17, blue: 0.17, alpha: 1))
    static let surface = adaptive(light: .white, dark: NSColor(red: 0.18, green: 0.19, blue: 0.19, alpha: 1))
    static let line = adaptive(light: NSColor(red: 0.88, green: 0.88, blue: 0.85, alpha: 1), dark: NSColor(red: 0.29, green: 0.30, blue: 0.30, alpha: 1))
    static let green = adaptive(light: forest, dark: mint)
    /// Amber is reserved for warnings and attention states so rust stays interaction and brand.
    static let warning = adaptive(light: amber, dark: gold)
    /// Native-feeling error red for failed outcomes; rust stays interaction and brand.
    static let error = adaptive(light: red, dark: salmon)
    /// Primary action fill: charcoal in light, rust in dark, always with white text.
    static let primaryFill = adaptive(light: NSColor(red: 0.15, green: 0.17, blue: 0.17, alpha: 1), dark: rust)
    static let onPrimary = Color.white
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
            .foregroundStyle(Theme.onPrimary).background(Theme.primaryFill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 7)).opacity(isEnabled ? 1 : 0.4)
    }
}
struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(Theme.ink).background(configuration.isPressed ? Theme.line : Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1)).opacity(isEnabled ? 1 : 0.4)
    }
}
struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @FocusState private var searchFocused: Bool
    var body: some View {
        @Bindable var model = model
        @Bindable var features = features
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                if showsTopbar { topbar; Divider().overlay(Theme.line) }
                sectionBar
                if isCurrentSection(.developer) { developerTabs }
                if model.reviewPreparing { HStack { BusyLine(text: "Preparing cleanup review…"); Spacer(); Button("Cancel review") { model.cancelReview() }.buttonStyle(QuietButton()) }.padding(.horizontal, 24).padding(.vertical, 10) }
                DiskQueueNotice()
                if model.page == .storage {
                    if model.mainWindowVisible { StorageView().padding(24) } else { Spacer() }
                } else if model.page == .duplicates {
                    if model.mainWindowVisible { DuplicatesView().padding(24) } else { Spacer() }
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
                        case .updates: UpdatesView()
                        case .aiAssist: AIAssistSettingsView()
                        case .growth: GrowthView()
                        case .projects: ProjectsView()
                        case .apps: ApplicationsView()
                        case .duplicates: DuplicatesView()
                        case .ai: AIStorageView()
                        case .devices: DevicesView()
                        case .monitor: MonitorSettingsView()
                        case .overview: OverviewView()
                        case .storage: StorageView()
                        case .developer: DeveloperView()
                        case .trash: TrashCleanupView()
                        case .docker: DockerView()
                        case .watchlist: WatchlistView()
                        case .history: ReceiptsView()
                        }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.id(model.page)
                }
                if model.page == .findSpace && !model.quickSelectedItems.isEmpty {
                    HStack {
                        Text("\(model.quickSelectedItems.count) selected · \(bytes(model.quickSelectedItems.reduce(0) { $0 + $1.size }))").font(.system(size: 12))
                        Spacer()
                        Button("Add to basket") { model.addToBasket(model.quickSelectedItems) }
                            .buttonStyle(QuietButton()).disabled(model.quick.busy || model.actionBusy)
                        Button("Review selected…") { model.reviewTrash(model.quickSelectedItems) }
                            .buttonStyle(PrimaryButton()).disabled(model.quick.busy || model.actionBusy)
                    }
                    .padding(14).background(Theme.surface)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Theme.paper)
        }.foregroundStyle(Theme.ink).tint(Theme.orange)
        .sheet(isPresented: $model.showTrashReview) { TrashReview() }
        .sheet(isPresented: $model.showCleanupBasket, onDismiss: { model.reviewBasketIfRequested() }) { CleanupBasketView() }
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
            guard url.scheme?.lowercased() == AppEnvironment.urlScheme else { return }
            if url.host == "storage" { model.page = .storage }
            if url.host == "monitor" { model.page = .monitor }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: [features.projectLoading, features.appLoading, features.duplicateLoading, features.aiLoading, features.deviceLoading, model.scanning]) { _, _ in
            if ProcessInfo.processInfo.arguments.contains("--capture") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { AppDelegate.capture(name: model.page.rawValue.lowercased()) }
            }
        }

        .alert("Nuke Sweep", isPresented: Binding(get: { model.message != nil || features.error != nil }, set: { if !$0 { model.message = nil; features.error = nil } })) { Button("Done") { model.message = nil; features.error = nil }; if model.recovery != nil { Button("Review access and retry") { model.message = nil; features.error = nil; model.page = .permissions } } } message: { Text(model.message ?? features.error ?? "") }
        .onChange(of: model.page) { _, newPage in
            if ProcessInfo.processInfo.arguments.contains("--capture") { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { AppDelegate.capture(name: newPage.rawValue.lowercased()) } }
            if newPage == .trash { model.inspectTrash() }
            if !ProcessInfo.processInfo.arguments.contains("--demo-fixtures") {
                if newPage == .docker { model.inspectDocker() }
            }
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
                Button { model.showCleanupBasket = true } label: {
                    HStack(spacing: 11) { Image(systemName: "tray").frame(width: 19); Text("Basket"); Spacer(); Text(String(model.cleanupBasket.items.count)).monospacedDigit().foregroundStyle(Theme.secondary) }
                        .font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 12)
                }.buttonStyle(.plain).accessibilityLabel("Cleanup basket, \(model.cleanupBasket.items.count) items")
                coreNav("History", icon: "clock.arrow.circlepath", section: .history, destination: .history)
            }.padding(.horizontal, 12)
            Spacer(minLength: 12)
            coreNav("Settings", icon: "gearshape", section: .settings, destination: .monitor).padding(.horizontal, 12).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) { Circle().fill(Theme.green).frame(width: 6, height: 6); Text("On this Mac").font(.system(size: 11, weight: .medium)) }
                HStack(spacing: 9) { Image(systemName: "laptopcomputer").font(.system(size: 15)); VStack(alignment: .leading, spacing: 2) { Text(Host.current().localizedName ?? "This Mac").font(.system(size: 11, weight: .semibold)).lineLimit(1) } }
                Text("Nuke Sweep " + UpdateChecker.installed + (AppEnvironment.isDevelopment ? " · Development" : "")).font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 16)
        }.frame(width: 202).background(Theme.rail)
    }
    func coreNav(_ title: LocalizedStringKey, icon: String, section: NavigationSection, destination: Page) -> some View {
        Button { model.page = destination } label: {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 19); Text(title); Spacer() }
                .font(.system(size: 13, weight: model.page.section == section ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(model.page.section == section ? (colorScheme == .dark ? Theme.orange.opacity(0.16) : Theme.surface) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(model.page.section == section ? .isSelected : [])
    }
    @ViewBuilder var sectionBar: some View {
        let pages: [Page] = model.page.section == .cleanup ? [.findSpace, .developer, .trash] : model.page.section == .files ? [.storage, .duplicates, .growth, .watchlist] : model.page.section == .settings ? [.monitor, .permissions, .alerts, .aiAssist, .updates] : []
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
    func tabTitle(_ page: Page) -> LocalizedStringKey {
        page == .findSpace ? "Check" : page.title
    }
    func isCurrentSection(_ tab: Page) -> Bool {
        if tab == .developer { return [.developer, .projects, .docker, .devices, .ai].contains(model.page) }
        return model.page == tab
    }
    private var developerTabs: some View {
        HStack(spacing: 4) {
            ForEach([Page.developer, .projects, .docker, .devices, .ai]) { page in
                let selected = model.page == page
                Button(page == .developer ? "Caches" : page.title) { model.page = page }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selected ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background(Theme.rail)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Developer tools")
    }
    var showsTopbar: Bool { model.page == .storage }
    var topbar: some View {
        HStack(spacing: 12) {
            Spacer()
            if model.page == .storage {
                HStack { Image(systemName: "magnifyingglass"); TextField("Filter \(model.page == .storage ? "files" : "processes")", text: Bindable(model).search).textFieldStyle(.plain).accessibilityLabel("Filter files or processes").focused($searchFocused) }.font(.system(size: 11)).padding(8).frame(width: 185).background(Theme.surface, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            }
            Button { model.refreshResources() } label: { Image(systemName: "arrow.clockwise").padding(7) }.buttonStyle(.plain).help("Refresh Mac storage and load").accessibilityLabel("Refresh Mac storage")
        }.padding(.horizontal, 24).frame(height: 40)
            .onChange(of: model.focusFilterRequest) { _, _ in searchFocused = true }
    }
    var pageHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.page.title).font(.system(size: 23, weight: .semibold)).tracking(-0.4)
                Text(model.page.localizedSubtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
/// Takes `LocalizedStringKey` rather than `String` so a literal written at a call
/// site is a translation key, the same way SwiftUI's own `Text` behaves. Use the
/// `verbatim:` initializer for text assembled at runtime, which must not be
/// looked up as a key.
struct SectionTitle: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey = ""
    private var detailVerbatim: String?
    private var titleVerbatim: String?
    init(title: LocalizedStringKey, detail: LocalizedStringKey = "") {
        self.title = title; self.detail = detail; self.detailVerbatim = nil; self.titleVerbatim = nil
    }
    /// Static factories rather than overloaded initializers: competing inits on a
    /// component used at ~90 call sites multiply the type checker's work enough to
    /// push large view bodies past its time limit.
    static func measured(title: LocalizedStringKey, detail: String) -> SectionTitle {
        var view = SectionTitle(title: title); view.detailVerbatim = detail; return view
    }
    static func measured(title: String, detail: String = "") -> SectionTitle {
        var view = SectionTitle(title: ""); view.titleVerbatim = title; view.detailVerbatim = detail; return view
    }
    var body: some View {
        HStack {
            Group { if let titleVerbatim { Text(verbatim: titleVerbatim) } else { Text(title) } }
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Group { if let detailVerbatim { Text(verbatim: detailVerbatim) } else { Text(detail) } }
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }
}
/// Extracted from the Files toolbar: a nested Menu/ForEach/Button chain inside an
/// already-large body pushes the enclosing expression past the type-checker's
/// time limit, and the compiler fails rather than slows down.
struct VolumesMenu: View {
    let volumes: [MountedVolume]
    let onSelect: (URL) -> Void
    var body: some View {
        Menu {
            if volumes.isEmpty {
                Text("No mounted volumes found")
            } else {
                ForEach(volumes) { volume in
                    let label: String = volume.name + " · " + volume.detail
                    Button {
                        FolderAccess.shared.remember(volume.url)
                        onSelect(volume.url)
                    } label: {
                        Text(verbatim: label)
                    }
                }
            }
        } label: {
            Label("Volumes", systemImage: "externaldrive")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Choose a mounted volume")
    }
}
/// Extracted from StorageView alongside StorageSummaryBar, for the same reason.
struct StorageToolbar: View {
    @Environment(AppModel.self) var model
    let volumes: [MountedVolume]
    var body: some View {
        HStack(spacing: 10) {
            Button {
                let parent = model.scanRoot.deletingLastPathComponent()
                model.scan(parent)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(QuietButton()).help("Scan parent folder")
            .accessibilityLabel("Scan parent folder").disabled(model.scanning)
            FolderBreadcrumbs(root: model.scanRoot, busy: model.scanning) { model.scan($0) }
            Spacer()
            VolumesMenu(volumes: volumes) { model.scan($0) }
            Button("Choose folder…") { model.chooseFolder() }.buttonStyle(QuietButton())
            Button("Full scan") { model.scan(force: true) }.buttonStyle(QuietButton()).disabled(model.scanning)
            Button("Refresh folder") { model.scan() }.buttonStyle(PrimaryButton()).disabled(model.scanning)
        }
    }
}
/// Extracted from StorageView: its body had grown past the point where the type
/// checker could resolve the whole expression, and the compiler fails outright
/// rather than merely slowing down. Keeping measured values out of the
/// ViewBuilder also keeps the localization keys free of interpolated numbers.
struct StorageSummaryBar: View {
    let result: ScanResult
    @Binding var useTree: Bool
    var body: some View {
        let partial: String = result.limited || result.skipped > 0 ? "+" : ""
        let size: String = bytes(result.logical) + partial
        HStack(spacing: 20) {
            Text("\(size) logical size").fontWeight(.semibold)
            Text("\(result.items.count) items")
            Spacer()
            Text("Largest first").foregroundStyle(Theme.secondary)
            Picker("Files view", selection: $useTree) {
                Text("Table").tag(false)
                Text("Tree").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 128)
            .help("Table lists one level; Tree expands folders in place. Search temporarily shows the table. Clear the search to return to the tree.")
        }
        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
    }
}
struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)) }
}
struct StorageMeter: View {
    @Environment(AppModel.self) var model
    @Environment(LiveMonitor.self) var monitor
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
    @Environment(AppModel.self) var model
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
                    actionRow("Check this Mac", detail: "One pass over caches, build output and Trash.", symbol: "sparkle.magnifyingglass", color: Color(red: 0.35, green: 0.38, blue: 0.58)) { model.page = .findSpace }
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
                Image(systemName: "calendar.badge.clock").font(.system(size: 21)).foregroundStyle(Theme.green).padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) { Text("Catch the growth before the cleanup.").font(.system(size: 14, weight: .semibold)); Text("Measure a folder on a schedule and see how its size changes over time.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                Spacer(); Button("Set up a schedule") { model.page = .watchlist }.buttonStyle(QuietButton())
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
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var showInsights = false
    @State private var showAccessIssues = false
    @AppStorage("nuke.filesViewMode") private var prefersTree = true
    @State private var tree = FolderTreeStore()
    @State private var treeSelection: [String: DiskItem] = [:]
    @State private var volumes: [MountedVolume] = []
    @State private var inspectedID: String?
    @State private var inspectedItem: DiskItem?
    private var useTree: Bool { prefersTree && model.search.isEmpty }
    private var viewMode: Binding<Bool> {
        Binding(get: { useTree }, set: { tree in
            prefersTree = tree
            if tree { model.search = "" }
        })
    }
    var activeItems: [DiskItem] { useTree ? treeSelection.values.sorted { $0.size > $1.size } : model.selectedItems }

    private func savePlanScope(_ excluded: [DiskItem]) {
        let root = model.scanRoot.standardizedFileURL
        let existing = features.developerScopes.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == root })
        let before = existing?.exclusions.count ?? 0
        let scope = DeveloperScope.applyingPlanExclusions(root: root, existing: existing, additions: excluded.map(\.url))
        features.upsertDeveloperScope(scope)
        features.measureDeveloperScope(scope)
        features.scopeStatus = "Saved \(scope.displayName) with \(scope.exclusions.count - before) new AI exclusion\(scope.exclusions.count - before == 1 ? "" : "s"). Access is not granted automatically."
        model.page = .developer
    }
    /// Built as a String rather than inline: a nested ternary with an interpolation
    /// is slow enough to type-check that it broke the enclosing body, and it made a
    /// useless localization key. Each branch is now its own translatable sentence.
    private func partialScanNotice(_ result: ScanResult) -> String {
        let cause: String
        if model.scanState.hasPrefix("Stopped") {
            cause = String(localized: "Stopped — partial results. Scan again to finish.")
        } else if result.limited {
            cause = String(localized: "Scan limit reached — partial results. Scan a smaller folder.")
        } else {
            let format = String(localized: "Access incomplete — %lld unreadable or skipped locations. Resolve access and retry.")
            cause = String(format: format, result.skipped)
        }
        return cause + " " + String(localized: "Totals may be incomplete.")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorageToolbar(volumes: volumes)
            if let result = model.result {
                if !model.scanning {
                    HStack(spacing: 6) {
                        if model.scanState.hasPrefix("Stopped") || model.scanState.contains("partial") || model.scanState.contains("incomplete") {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Theme.warning)
                        }
                        // Built outside the ViewBuilder: inferring this concatenation
                        // inline pushes the enclosing expression past the
                        // type-checker's time limit.
                        let state: String = model.scanState + (model.resultMeasured.map { " · " + $0.formatted() } ?? "")
                        Text(verbatim: state).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                }
                StorageSummaryBar(result: result, useTree: viewMode)
                if result.skipped > 0 || result.limited { Notice.measured(partialScanNotice(result), symbol: "exclamationmark.triangle") }
                if result.skipped > 0 {
                    DisclosureGroup("Access issues", isExpanded: $showAccessIssues) {
                        ForEach(Array(result.accessIssues.prefix(3).enumerated()), id: \.offset) { _, issue in
                            Text(issue.path + ": " + issue.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                        }
                        AccessRecovery()
                    }.font(.system(size: 12))
                }
                Button {
                    showInsights.toggle()
                } label: {
                    Label("Storage map and suggestions", systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .popover(isPresented: $showInsights, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            StorageTreemap(items: result.items)
                            TriagePanel(store: model.triage)
                        }.padding(16)
                    }.frame(width: 540, height: 420)
                }
                HSplitView {
                    Group {
                        if useTree {
                            FolderTreeView(store: tree, selection: $treeSelection, items: result.items, blocked: { DeveloperScope.cleanupBlock(for: $0.url.standardizedFileURL.path, in: features.developerScopes) != nil }, onSaveAsScope: savePlanScope, onInspect: { inspectedItem = $0 })
                        } else { fileTable }
                    }.frame(minWidth: 350, maxHeight: .infinity)
                    Group {
                        if let inspectedItem {
                            ItemDetailsView(item: inspectedItem).id(inspectedItem.id)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Item details").font(.system(size: 14, weight: .semibold))
                                Text("Click a file or folder to see its size and cleanup assessment. Use checkboxes to select items for cleanup.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                Spacer()
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.frame(minWidth: 220, idealWidth: 255, maxWidth: 340, maxHeight: .infinity)
                        .background(Theme.surface)
                }.frame(maxHeight: .infinity)
                HStack { Text("\(bytes(result.allocated))\(result.limited || result.skipped > 0 ? "+" : "") allocated · APFS sharing and hard links can affect totals. Trash does not immediately free space.").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer() }
                HStack(spacing: 8) {
                    Text("\(activeItems.count) selected").font(.system(size: 11))
                    if useTree && !activeItems.isEmpty { Text("· folders move with their contents").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    Spacer()
                    Button("Add to basket") { model.addToBasket(activeItems) }.buttonStyle(QuietButton()).disabled(activeItems.isEmpty || model.actionBusy || model.scanning)
                    Button("Review selected…") { model.reviewTrash(activeItems) }.buttonStyle(PrimaryButton()).disabled(activeItems.isEmpty || model.actionBusy || model.scanning)
                }
            } else if !model.scanning {
                // These choices already existed as bare buttons under a paragraph.
                // Routed through SuggestedStart so every screen's starting point
                // looks and reads the same, and each option says why it is offered.
                SuggestedStart(
                    title: "Start with a folder",
                    detail: "Scan anywhere you would like to understand. Hidden items are included and symbolic links are not followed.",
                    symbol: "folder.badge.magnifyingglass",
                    choices: StartingPoints.forBrowsing.map { url, detail in
                        .init(url: url, detail: detail) { model.scan(url) }
                    }
                )
            }
        }
        .onChange(of: model.treeResetToken) { _, _ in tree.reset(); treeSelection = [:] }
        .onChange(of: model.scanRoot) { _, _ in tree.reset(); treeSelection = [:]; inspectedItem = nil; inspectedID = nil }
        .onChange(of: inspectedID.flatMap { id in model.visibleItems.first { $0.id == id } }) { _, item in
            if !useTree { inspectedItem = item }
        }
        .onAppear { volumes = MountedVolumeService.list() }
        .onChange(of: model.finishedReceipt?.id) { _, _ in tree.reset(); treeSelection = [:] }
        .onChange(of: useTree) {
            inspectedID = nil
            inspectedItem = nil
        }
    }
    var fileTable: some View {
        Table(model.visibleItems, selection: $inspectedID) {
            TableColumn("") { item in
                Toggle("Select \(item.name)", isOn: Binding(get: { model.selected.contains(item.id) }, set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }))
                    .labelsHidden().toggleStyle(.checkbox).disabled(item.incomplete || model.actionBusy || model.scanning || DeveloperScope.cleanupBlock(for: item.url.standardizedFileURL.path, in: features.developerScopes) != nil)
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

struct DiskQueueNotice: View {
    private let activity = DiskActivity.shared
    var body: some View {
        if !activity.running.isEmpty {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(activity.running).fontWeight(.medium); if activity.waiting > 0 { Text("· \(activity.waiting) queued") }; if let started = activity.started { Text(started, style: .relative).monospacedDigit() } }
                    if !activity.path.isEmpty { Text("\(activity.visited) entries · " + activity.path).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.secondary) }
                }.font(.system(size: 11))
                Spacer()
                Menu("Tasks · \(activity.jobs.count)") {
                    ForEach(activity.jobs) { job in
                        Section(job.label) {
                            Text(job.state + (job.visited > 0 ? " · \(job.visited) entries" : ""))
                            if !job.path.isEmpty { Text(job.path) }
                            Button("Stop this task") { activity.stop(job.id) }.disabled(!job.canStop)
                        }
                    }
                }.font(.system(size: 11)).fixedSize()
                if activity.canStop { Button("Stop") { activity.stop() }.buttonStyle(QuietButton()) }
            }.padding(.horizontal, 24).padding(.vertical, 10)
                .background(Theme.rail.opacity(0.78))
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .contain)
        }
    }
}

extension Page {
    /// The English name, used where a plain `String` is required — accessibility
    /// strings built by interpolation, `help(_:)`, capture filenames. Derived from
    /// `rawValue`, which is persisted in the saved workspace and must stay stable.
    var sidebarTitle: String { self == .developer ? "Developer" : self == .monitor ? "General" : self == .storage ? "Browse" : rawValue }

    /// The translatable display name.
    ///
    /// Spelled out as literals rather than `LocalizedStringKey(sidebarTitle)`:
    /// a key built from a runtime string is invisible to `scripts/extract-strings.py`,
    /// so it would never reach a catalogue and would silently never translate.
    /// `rawValue` stays the stable persistence key; this is only ever displayed.
    var title: LocalizedStringKey {
        switch self {
        case .findSpace: return "Cleanup"
        case .alerts: return "Alerts"
        case .permissions: return "Permissions & access"
        case .updates: return "Updates"
        case .aiAssist: return "AI assist"
        case .growth: return "Growth"
        case .projects: return "Projects"
        case .apps: return "Applications"
        case .duplicates: return "Duplicates"
        case .ai: return "Local models"
        case .devices: return "Devices"
        case .monitor: return "General"
        case .overview: return "Overview"
        case .storage: return "Browse"
        case .developer: return "Developer"
        case .trash: return "Trash"
        case .docker: return "Docker"
        case .watchlist: return "Schedules"
        case .history: return "History"
        }
    }

    /// The translatable one-line description shown under a page heading.
    var localizedSubtitle: LocalizedStringKey {
        switch self {
        case .findSpace: return "Review caches, developer storage, your own surplus files, and Trash."
        case .alerts: return "Understand growth and choose what deserves attention."
        case .permissions: return "Choose folder access and recover from denied scans."
        case .updates: return "Check for a newer public release."
        case .aiAssist: return "Explain ambiguous storage with an optional AI provider. Advisory only."
        case .growth: return "See what changed between complete folder scans."
        case .projects: return "Build output, dependencies, and Compose resources by project."
        case .apps: return "Review applications and the files that may belong to them."
        case .duplicates: return "Compare exact file contents and choose a copy to keep."
        case .ai: return "Understand local model storage before downloading it again."
        case .devices: return "Review emulator storage, archives, and device backups."
        case .monitor: return "Appearance, the menu-bar tool, and diagnostics."
        case .overview: return "A clearer picture of what’s on your Mac."
        case .storage: return "Follow the space. Keep what matters."
        case .developer: return "Build artifacts and caches, with the context to clean them."
        case .trash: return "Review what’s in Trash before letting it go for good."
        case .docker: return "Know what your containers leave behind."
        case .watchlist: return "Measure a folder on a schedule and see how it changes."
        case .history: return "A record of the changes you’ve made with Nuke Sweep."
        }
    }
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

/// The headline the Developer screen was missing: what all the measured
/// locations add up to, and how much of that comes back cheaply.
