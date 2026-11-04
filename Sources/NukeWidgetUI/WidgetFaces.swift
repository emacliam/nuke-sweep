import SwiftUI
import NukeMetrics

public enum WidgetPalette {
    public static let accent = Color(red: 0.76, green: 0.27, blue: 0.13)
    public static func accent(for scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.97, green: 0.61, blue: 0.43) : accent }
    public static func background(for scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.13) : paper }
    public static let paper = Color(red: 0.985, green: 0.981, blue: 0.969)
}
public func widgetBytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—" }

public struct StorageWidgetFace: View {
    @Environment(\.colorScheme) private var colorScheme
    public let metrics: WidgetMetrics
    public let compact: Bool
    public init(metrics: WidgetMetrics, compact: Bool) { self.metrics = metrics; self.compact = compact }
    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 13) {
            HStack(spacing: 6) {
                SweepMark(monochrome: colorScheme == .dark).frame(width: 14, height: 12)
                Text("Nuke Sweep Storage").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if !compact { Image(systemName: "internaldrive").foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(widgetBytes(metrics.freeDisk)).font(.system(size: compact ? 27 : 31, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(metrics.freeDisk == nil ? "Measurement unavailable" : "Available on this volume").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let fraction = metrics.usedFraction {
                ProgressView(value: fraction).tint(WidgetPalette.accent(for: colorScheme)).accessibilityLabel("Storage \(Int(fraction * 100)) percent used")
                if !compact { Text("\(widgetBytes(metrics.totalDisk)) total · \(Int(fraction * 100))% used").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) { Text("Updated"); Text(metrics.date, style: .time) }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
public struct ResourcesWidgetFace: View {
    @Environment(\.colorScheme) private var colorScheme
    public let metrics: WidgetMetrics
    public let compact: Bool
    public init(metrics: WidgetMetrics, compact: Bool) { self.metrics = metrics; self.compact = compact }
    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(spacing: 6) { SweepMark(monochrome: colorScheme == .dark).frame(width: 14, height: 12); Text("Nuke Sweep Resources") }.font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetPalette.accent(for: colorScheme))
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 5) { Text(cpu).font(.system(size: 27, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6); Text("CPU").font(.system(size: 10)).foregroundStyle(.secondary) }
                Text("Memory \(widgetBytes(metrics.memory))").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    metric(cpu, "CPU snapshot")
                    metric(widgetBytes(metrics.memory), "Active + wired + compressed")
                    metric(widgetBytes(metrics.freeDisk), "Storage available")
                }
            }
            Spacer(minLength: 0)
            Text("Snapshot, not a live monitor").font(.system(size: 9)).foregroundStyle(.secondary)
            HStack(spacing: 4) { Text("Updated"); Text(metrics.date, style: .time) }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var cpu: String { metrics.cpu.map { String(format: "%.0f%%", $0) } ?? "—" }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6); Text(label).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
