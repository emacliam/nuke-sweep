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
struct StorageTreemap: View {
    @EnvironmentObject var model: AppModel
    let items: [DiskItem]
    private var inspected: String? { get { model.focusedStorageItem } nonmutating set { model.focusedStorageItem = newValue } }
    private let colors: [Color] = [Color(red: 0.65, green: 0.22, blue: 0.10), Color(red: 0.25, green: 0.36, blue: 0.32), Color(red: 0.29, green: 0.36, blue: 0.44), Color(red: 0.47, green: 0.30, blue: 0.24), Color(red: 0.39, green: 0.33, blue: 0.43)]
    var blocks: [StorageBlock] { StorageMapLayout.blocks(items) }
    var selected: StorageBlock? { blocks.first { $0.id == inspected } ?? blocks.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Where the space goes", detail: "Area represents measured logical bytes")
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
                            if item.directory && !item.symlink { Button("Scan inside") { model.scan(item.url) }.buttonStyle(QuietButton()).disabled(model.scanning) }
                            Button("Review cleanup…") { model.reviewTrash([item]) }.buttonStyle(QuietButton()).disabled(model.actionBusy || item.incomplete).help("Remeasure this item and verify access before reviewing cleanup")
                        }
                    }.font(.system(size: 11))
                }
                Text("Up to 24 largest items, with the remainder grouped. Zero-byte items stay in the list below. Review remeasures the chosen item and verifies access. Partial measurements remain partial; area does not mean reclaimable space.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }.onChange(of: items.map(\.id)) { _, ids in if let inspected, !ids.contains(inspected) { self.inspected = nil } }
    }
    func mapButton(_ tile: MapTile, color: Color) -> some View {
        Button { inspected = tile.id } label: {
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
        .help(tile.block.name + " · " + bytes(tile.block.size))
        .accessibilityLabel(tile.block.name + ", " + bytes(tile.block.size) + ". Inspect size.")
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
            SectionTitle(title: "Folder size over time", detail: "Complete scans · " + scale.unit)
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
            SectionTitle(title: "Largest changes", detail: "Up to 10 items · " + scale.unit)
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
