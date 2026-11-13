import SwiftUI
import Charts

struct StorageBlock: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let item: DiskItem?
}
struct MapTile: Identifiable {
    let block: StorageBlock
    let rect: CGRect
    var id: String { block.id }
}
enum StorageMapLayout {
    static func blocks(_ items: [DiskItem]) -> [StorageBlock] {
        let sorted = items.filter { $0.size > 0 }.sorted { $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size }
        var result = sorted.prefix(24).map { StorageBlock(id: $0.id, name: $0.name, size: $0.size, item: $0) }
        let rest = sorted.dropFirst(24)
        if !rest.isEmpty { result.append(StorageBlock(id: "aggregate:other", name: "Other \(rest.count) items", size: rest.reduce(0) { $0 + $1.size }, item: nil)) }
        return result
    }
    static func tiles(_ blocks: [StorageBlock], in rect: CGRect) -> [MapTile] {
        let blocks = blocks.filter { $0.size > 0 }
        guard !blocks.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        if blocks.count == 1 { return [MapTile(block: blocks[0], rect: rect)] }
        let total = blocks.reduce(0.0) { $0 + Double($1.size) }
        var split = 1, prefix = Double(blocks[0].size)
        while split < blocks.count - 1 && abs(prefix + Double(blocks[split].size) - total / 2) < abs(prefix - total / 2) {
            prefix += Double(blocks[split].size); split += 1
        }
        let fraction = prefix / total
        let first: CGRect, second: CGRect
        if rect.width >= rect.height {
            let width = rect.width * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            second = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * fraction
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            second = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
        return tiles(Array(blocks[..<split]), in: first) + tiles(Array(blocks[split...]), in: second)
    }
}
/// One level of the map's navigation stack.
private struct MapLevel: Identifiable {
    let id: String
    let name: String
    let items: [DiskItem]
}

struct StorageTreemap: View {
    @Environment(AppModel.self) var model
    let items: [DiskItem]
    /// Folders drilled into, deepest last. Empty means the scan root is showing.
    @State private var stack: [MapLevel] = []
    @State private var loading = false
    @State private var listingToken = ScanCancellation()
    private var inspected: String? { get { model.focusedStorageItem } nonmutating set { model.focusedStorageItem = newValue } }
    private let colors: [Color] = [Color(red: 0.65, green: 0.22, blue: 0.10), Color(red: 0.25, green: 0.36, blue: 0.32), Color(red: 0.29, green: 0.36, blue: 0.44), Color(red: 0.47, green: 0.30, blue: 0.24), Color(red: 0.39, green: 0.33, blue: 0.43)]
    /// What the map is currently showing: the scan root, or the folder drilled into.
    private var visibleItems: [DiskItem] { stack.last?.items ?? items }
    var blocks: [StorageBlock] { StorageMapLayout.blocks(visibleItems) }

    /// Lists a folder's children on the interactive lane and pushes a level.
    /// Measuring is bounded, so a huge folder cannot stall the map; sizes that
    /// did not finish measuring are marked incomplete like anywhere else.
    private func drill(into item: DiskItem) {
        guard item.directory, !item.symlink, !loading else { return }
        listingToken.cancel()
        let token = ScanCancellation(); listingToken = token
        loading = true
        Task {
            let listed = await DiskWork.run("Opening " + item.name, lane: .interactive, cancellation: token) {
                let result = FolderListing.inspect(item.url, token: token)
                return FolderListing.measure(result.items, token: token, excluding: { _ in false })
            }
            guard !token.cancelled else { return }
            loading = false
            guard !listed.isEmpty else { return }
            stack.append(MapLevel(id: item.id, name: item.name, items: listed))
            inspected = nil
        }
    }

    private func pop(to index: Int?) {
        listingToken.cancel(); loading = false
        if let index { stack = Array(stack.prefix(index + 1)) } else { stack = [] }
        inspected = nil
    }

    @ViewBuilder private var breadcrumbs: some View {
        if !stack.isEmpty {
            HStack(spacing: 4) {
                Button("Scan root") { pop(to: nil) }
                    .buttonStyle(.plain).foregroundStyle(Theme.orange)
                ForEach(Array(stack.enumerated()), id: \.element.id) { index, level in
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.secondary)
                    Button {
                        pop(to: index)
                    } label: {
                        Text(verbatim: level.name).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == stack.count - 1 ? Theme.ink : Theme.orange)
                    .disabled(index == stack.count - 1)
                }
                if loading { Text("Opening…").foregroundStyle(Theme.secondary) }
                Spacer()
            }
            .font(.system(size: 11))
            .accessibilityLabel("Map location: " + stack.map(\.name).joined(separator: ", then "))
        }
    }
    var selected: StorageBlock? { blocks.first { $0.id == inspected } ?? blocks.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Where the space goes", detail: "Area represents measured logical bytes")
            breadcrumbs
            if blocks.isEmpty { Text("No positive file sizes to plot.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            else {
                GeometryReader { geometry in
                    let tiles = StorageMapLayout.tiles(blocks, in: CGRect(origin: .zero, size: geometry.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            mapButton(tile, color: colors[index % colors.count])
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading).clipped()
                }.frame(height: 260)
                if let selected {
                    HStack {
                        Text(selected.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        Text(bytes(selected.size)).monospacedDigit(); Spacer()
                        if let item = selected.item {
                            Button("Reveal") { model.reveal(item.url) }.buttonStyle(QuietButton())
                            if item.directory && !item.symlink {
                                Button("Open here") { drill(into: item) }.buttonStyle(QuietButton()).disabled(loading)
                                    .help("Show this folder's contents in the map without leaving the page")
                                Button("Scan inside") { model.scan(item.url) }.buttonStyle(QuietButton()).disabled(model.scanning)
                                    .help("Make this folder the scan root")
                            }
                            Button("Review cleanup…") { model.reviewTrash([item]) }.buttonStyle(QuietButton()).disabled(model.actionBusy || item.incomplete).help("Remeasure this item and verify access before reviewing cleanup")
                        }
                    }.font(.system(size: 11))
                }
                Text("Up to 24 largest items, with the remainder grouped. Zero-byte items stay in the list below. Review remeasures the chosen item and verifies access. Partial measurements remain partial; area does not mean reclaimable space.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            // A fresh scan replaces what the map is drawn from, so a drill stack
            // built on the old results would point at folders no longer shown.
            if !stack.isEmpty { pop(to: nil) }
            if let inspected, !ids.contains(inspected) { self.inspected = nil }
        }
        .onDisappear { listingToken.cancel() }
    }
    func mapButton(_ tile: MapTile, color: Color) -> some View {
        // Single click inspects, double click opens: the same convention Finder
        // uses, so the map can be read without being navigated by accident.
        Button {
            inspected = tile.id
        } label: {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(color)
                if tile.rect.width > 90 && tile.rect.height > 48 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.block.name).fontWeight(.semibold).lineLimit(2)
                        Text(bytes(tile.block.size)).monospacedDigit()
                    }.font(.system(size: 11)).foregroundStyle(.white).padding(10)
                }
            }.overlay(Rectangle().strokeBorder(Color.white, lineWidth: inspected == tile.id ? 3 : 1))
        }.buttonStyle(.plain).frame(width: tile.rect.width, height: tile.rect.height)
        .offset(x: tile.rect.minX, y: tile.rect.minY)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if let item = tile.block.item { drill(into: item) }
        })
        .help(tile.block.name + " · " + bytes(tile.block.size) + (tile.block.item?.directory == true ? " · double-click to open" : ""))
        .accessibilityLabel(tile.block.name + ", " + bytes(tile.block.size) + (tile.block.item?.directory == true ? ". Double-click to open." : ". Inspect size."))
    }

}
struct GrowthHistoryChart: View {
    let scans: [StoredScan]
    @State private var inspectedDate: Date?
    var chosen: StoredScan? { ChartInspection.nearest(scans, date: inspectedDate, dateOf: { $0.date }) }
    var scale: ChartByteScale { ChartByteScale(maximum: scans.map { Double($0.total) }.max() ?? 0) }
    var ordered: [StoredScan] { scans.sorted { $0.date < $1.date } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle.measured(title: "Folder size over time", detail: "Complete scans · " + scale.unit)
            if let chosen {
                HStack { Text(chosen.date.formatted(date: .abbreviated, time: .standard)); Spacer(); Text(bytes(chosen.total)).monospacedDigit().fontWeight(.medium) }.font(.system(size: 11))
                Picker("Inspect scan", selection: Binding(get: { chosen.id }, set: { id in inspectedDate = ordered.first { $0.id == id }?.date })) { ForEach(ordered) { Text($0.date.formatted(date: .abbreviated, time: .standard)).tag($0.id) } }.frame(maxWidth: 420)
            }
            Chart(ordered) { scan in
                LineMark(x: .value("Scan", scan.date), y: .value("Logical " + scale.unit, Double(scan.total) / scale.divisor)).foregroundStyle(Theme.orange)
                PointMark(x: .value("Scan", scan.date), y: .value("Logical " + scale.unit, Double(scan.total) / scale.divisor)).foregroundStyle(Theme.orange)
                    .accessibilityLabel(scan.date.formatted()).accessibilityValue(bytes(scan.total))
                if let chosen { RuleMark(x: .value("Inspected scan", chosen.date)).foregroundStyle(Theme.secondary.opacity(0.5)) }
            }.chartXSelection(value: $inspectedDate)
            .chartOverlay { proxy in DateChartOverlay(proxy: proxy, selection: $inspectedDate) }
            .chartYScale(domain: 0...max(0.001, (ordered.map { Double($0.total) / scale.divisor }.max() ?? 0) * 1.1)).frame(height: 210)
            Text("Hover or drag to inspect; use the scan picker with a keyboard. Points are saved scans, joined to show their order. Changes between scans were not observed.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }
}
struct GrowthChangeChart: View {
    let rows: [GrowthRow]
    @Binding var inspectedName: String?
    var scale: ChartByteScale { ChartByteScale(maximum: rows.map { abs(Double($0.delta)) }.max() ?? 0) }
    var chosen: GrowthRow? { plotted.first { $0.name == inspectedName } ?? plotted.first }
    var plotted: [GrowthRow] { Array(rows.filter { $0.delta != 0 }.prefix(10)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle.measured(title: "Largest changes", detail: "Up to 10 items · " + scale.unit)
            if plotted.isEmpty { Text("No measured size changes between these scans.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            else {
                if let chosen {
                    Picker("Inspect change", selection: Binding(get: { chosen.name }, set: { inspectedName = $0 })) { ForEach(plotted) { Text($0.name).tag($0.name) } }.frame(maxWidth: 420)
                    Text(changeDescription(chosen)).font(.system(size: 11)).textSelection(.enabled)
                }
                Chart(plotted) { row in
                    BarMark(x: .value("Change in " + scale.unit, Double(row.delta) / scale.divisor), y: .value("Item", row.name))
                        .foregroundStyle(row.delta > 0 ? Theme.orange : Theme.green)
                        .opacity(chosen?.name == row.name ? 1 : 0.6)
                        .accessibilityLabel(row.name).accessibilityValue((row.delta > 0 ? "Increased by " : "Decreased by ") + bytes(abs(row.delta)))
                    RuleMark(x: .value("No change", 0)).foregroundStyle(Theme.secondary)
                }.chartYSelection(value: $inspectedName)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            if case .active(let location) = phase, let frame = proxy.plotFrame { inspectedName = proxy.value(atY: location.y - geometry[frame].minY) }
                        }.gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            if let frame = proxy.plotFrame { inspectedName = proxy.value(atY: value.location.y - geometry[frame].minY) }
                        })
                    }
                }.chartYScale(domain: plotted.map(\.name)).chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 10)) } }
                .frame(height: CGFloat(max(140, plotted.count * 30)))
                Text("Left of zero: smaller. Right of zero: larger. Exact values are listed below.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
    }
    func changeDescription(_ row: GrowthRow) -> String {
        let sign = row.delta > 0 ? "+" : "−"
        return "\(row.name): \(bytes(row.before)) → \(bytes(row.after)) (\(sign)\(bytes(abs(row.delta))))"
    }

}
struct ResourceHistoryChart: View {
    let samples: [MonitorSample]
    var interval: TimeInterval = 5
    @AppStorage("nuke.resourceRange") private var range = 10.0
    var visibleSamples: [MonitorSample] { let end = samples.last?.date ?? Date(); return samples.filter { end.timeIntervalSince($0.date) <= range * 60 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recent resource activity", detail: "Current session · ending at the last sample")
            Picker("Chart range", selection: $range) { Text("2 minutes").tag(2.0); Text("5 minutes").tag(5.0); Text("10 minutes").tag(10.0) }.pickerStyle(.segmented).frame(width: 320)
            if visibleSamples.count < 2 { Text("Waiting for a second sample. Enable the menu-bar monitor to collect readings at the selected interval.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            else {
                resourceChart(memory: false)
                resourceChart(memory: true)
                Text("CPU uses a 0–100% scale. Memory is active + wired + compressed VM in decimal GB, not memory pressure. Unknown readings and interruptions in sampling break the line. Session history is kept in memory only.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }
    }
    func resourceChart(memory: Bool) -> some View { ResourceLineChart(samples: visibleSamples, memory: memory, interval: interval) }
}
struct ResourceLineChart: View {
    let samples: [MonitorSample]
    let memory: Bool
    let interval: TimeInterval
    @State private var inspectedDate: Date?
    var points: [ResourceChartPoint] { ResourceChartPoint.make(samples, memory: memory, maximumGap: max(15, interval * 2.5)) }
    var chosen: ResourceChartPoint? { ChartInspection.nearest(points, date: inspectedDate, dateOf: { $0.date }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(memory ? "VM memory · GB" : "CPU · %").fontWeight(.medium)
                Spacer()
                if let chosen { Text(chosen.date.formatted(date: .omitted, time: .standard)); Text(String(format: memory ? "%.2f GB" : "%.1f%%", chosen.value)).monospacedDigit() }
            }.font(.system(size: 11))
            Chart(points) { point in
                LineMark(x: .value("Sample", point.date), y: .value(memory ? "GB" : "Percent", point.value), series: .value("Continuous segment", point.segment))
                    .foregroundStyle(memory ? Theme.green : Theme.orange)
                PointMark(x: .value("Sample", point.date), y: .value(memory ? "GB" : "Percent", point.value)).symbolSize(8)
                    .foregroundStyle(memory ? Theme.green : Theme.orange)
                if let chosen, chosen.id == point.id { RuleMark(x: .value("Inspected sample", point.date)).foregroundStyle(Theme.secondary.opacity(0.5)) }
            }.chartXSelection(value: $inspectedDate)
            .chartOverlay { proxy in DateChartOverlay(proxy: proxy, selection: $inspectedDate) }
            .chartYScale(domain: 0...(memory ? max(1, (points.map(\.value).max() ?? 1) * 1.15) : 100)).frame(height: 140)
            if points.isEmpty { Text("No available readings in this interval.").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            else {
                Picker("Inspect " + (memory ? "memory" : "CPU") + " sample", selection: Binding(get: { chosen?.id ?? 0 }, set: { id in inspectedDate = points.first { $0.id == id }?.date })) { ForEach(points) { Text($0.date.formatted(date: .omitted, time: .standard)).tag($0.id) } }.frame(maxWidth: 300)
            }
        }
    }
}
struct DateChartOverlay: View {
    let proxy: ChartProxy
    @Binding var selection: Date?
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                if case .active(let location) = phase { inspect(location, geometry) }
            }.gesture(DragGesture(minimumDistance: 0).onChanged { inspect($0.location, geometry) })
        }
    }
    func inspect(_ location: CGPoint, _ geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let frame = geometry[anchor]
        guard frame.contains(location) else { return }
        selection = proxy.value(atX: location.x - frame.minX)
    }
}
enum ChartInspection {
    static func nearest<T>(_ points: [T], date: Date?, dateOf: (T) -> Date) -> T? {
        guard let date else { return points.max { dateOf($0) < dateOf($1) } }
        return points.min { abs(dateOf($0).timeIntervalSince(date)) < abs(dateOf($1).timeIntervalSince(date)) }
    }
}

struct ResourceChartPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
    let segment: Int
    static func make(_ samples: [MonitorSample], memory: Bool, maximumGap: TimeInterval = 15) -> [ResourceChartPoint] {
        var points: [ResourceChartPoint] = [], segment = 0
        var last: Date?
        for (index, sample) in samples.enumerated() {
            let value = memory ? sample.memory.map { Double($0) / 1e9 } : sample.cpu
            guard let value, value.isFinite, value >= 0 else { segment += 1; last = nil; continue }
            if let last, sample.date.timeIntervalSince(last) > maximumGap { segment += 1 }
            points.append(.init(id: index, date: sample.date, value: value, segment: segment)); last = sample.date
        }
        return points
    }
}

struct ChartByteScale: Equatable {
    let divisor: Double
    let unit: String
    init(maximum: Double) {
        if maximum >= 1e9 { divisor = 1e9; unit = "GB" }
        else if maximum >= 1e6 { divisor = 1e6; unit = "MB" }
        else if maximum >= 1e3 { divisor = 1e3; unit = "KB" }
        else { divisor = 1; unit = "bytes" }
    }
}

/// A donut over the measured areas, so "1 of 5 areas measured" is something you
/// see rather than read.
///
/// Unmeasured areas are drawn as a hatched remainder rather than omitted. A ring
/// showing only what has been scanned would imply the measured part is the whole
/// picture, which is the same dishonesty `ReclaimSummary` exists to avoid.
struct CompositionRing: View {
    let summary: ReclaimSummary
    var inspected: ReclaimSummary.Area?

    private var measured: [ReclaimSummary.Area] { summary.measuredAreas.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes } }
    private var total: Double { Double(max(1, summary.measuredBytes)) }
    private let palette: [Color] = [
        Color(red: 0.76, green: 0.27, blue: 0.13),
        Color(red: 0.25, green: 0.44, blue: 0.38),
        Color(red: 0.29, green: 0.36, blue: 0.52),
        Color(red: 0.55, green: 0.38, blue: 0.22),
        Color(red: 0.42, green: 0.33, blue: 0.48)
    ]

    func color(for area: ReclaimSummary.Area) -> Color {
        guard let index = measured.firstIndex(where: { $0.id == area.id }) else { return Theme.secondary }
        return palette[index % palette.count]
    }

    var body: some View {
        if measured.isEmpty {
            EmptyView()
        } else {
            ZStack {
                ForEach(Array(measured.enumerated()), id: \.element.id) { index, area in
                    let start = measured.prefix(index).reduce(0.0) { $0 + Double($1.bytes) } / total
                    let end = start + Double(area.bytes) / total
                    Circle()
                        .trim(from: start, to: end)
                        .stroke(color(for: area), style: StrokeStyle(lineWidth: inspected?.id == area.id ? 20 : 15, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(verbatim: bytes(summary.measuredBytes))
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Text("measured").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                bytes(summary.measuredBytes) + " measured across "
                    + measured.map { "\($0.name) \(bytes($0.bytes))" }.joined(separator: ", ")
                    + (summary.unmeasuredAreas.isEmpty ? "" : ". \(summary.unmeasuredAreas.count) areas not measured.")
            )
        }
    }
}

/// An empty screen that offers somewhere to start instead of describing one.
///
/// Several screens opened as a button and a paragraph, leaving the person to go
/// and find a folder the app could have suggested. These are suggestions only:
/// choosing one starts the same bounded scan the manual picker would, and
/// nothing is selected or cleaned by picking a starting point.
struct SuggestedStart: View {
    struct Choice: Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let action: () -> Void
        init(url: URL, detail: String, symbol: String = "folder", action: @escaping () -> Void) {
            self.id = url.path
            self.name = "~/" + url.lastPathComponent
            self.detail = detail
            self.symbol = symbol
            self.action = action
        }
        init(id: String, name: String, detail: String, symbol: String, action: @escaping () -> Void) {
            self.id = id; self.name = name; self.detail = detail; self.symbol = symbol; self.action = action
        }
    }

    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let choices: [Choice]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.orange)
                Text(title).font(.system(size: 19, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460, alignment: .leading)
            }
            if !choices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start here").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    ForEach(choices) { choice in
                        Button(action: choice.action) {
                            HStack(spacing: 10) {
                                Image(systemName: choice.symbol).foregroundStyle(Theme.orange).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: choice.name).font(.system(size: 12, weight: .medium))
                                    Text(verbatim: choice.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            .padding(11).contentShape(Rectangle())
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(choice.name). \(choice.detail)")
                    }
                }.frame(maxWidth: 460, alignment: .leading)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The folders where the thing each screen looks for actually tends to live.
enum StartingPoints {
    static func home(_ name: String) -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }
    /// Where duplicate files accumulate: download and working folders, not caches.
    static var forDuplicates: [(URL, String)] {
        [("Downloads", "Repeat downloads collect here"),
         ("Desktop", "Working copies and saved attachments"),
         ("Documents", "Versioned documents and exports")]
            .compactMap { name, detail in home(name).map { ($0, detail) } }
    }
    /// Where someone is most likely to want to look first.
    static var forBrowsing: [(URL, String)] {
        [("Downloads", "Usually the quickest win"),
         ("Documents", "Long-lived files worth understanding"),
         ("Desktop", "Accumulates without being noticed")]
            .compactMap { name, detail in home(name).map { ($0, detail) } }
    }
}

/// Counted phrases that follow the user's language rules rather than English's.
///
/// `count == 1 ? "" : "s"` is correct for English and wrong almost everywhere
/// else — Polish has three plural categories, Arabic six, Japanese none. A
/// ternary cannot express that and a translator cannot fix it from the catalogue.
/// These route through `Localizable.stringsdict`, where each language declares
/// the categories it needs.
enum Plural {
    static func items(_ count: Int) -> String { format("%lld items", count) }
    static func locations(_ count: Int) -> String { format("%lld locations", count) }
    static func projects(_ count: Int) -> String { format("%lld projects", count) }
    static func copies(_ count: Int) -> String { format("%lld copies", count) }
    static func otherLocations(_ count: Int) -> String { format("%lld other locations", count) }
    static func heldBack(_ count: Int) -> String { format("%lld items held back", count) }
    static func areasMeasured(_ count: Int) -> String { format("%lld areas measured", count) }

    private static func format(_ key: String, _ count: Int) -> String {
        String(format: NSLocalizedString(key, comment: ""), count)
    }
}
