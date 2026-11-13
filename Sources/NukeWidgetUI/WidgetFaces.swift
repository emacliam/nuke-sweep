import SwiftUI
import NukeMetrics

public enum WidgetPalette {
    public static let accent = Color(red: 0.76, green: 0.27, blue: 0.13)
    public static func accent(for scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.97, green: 0.61, blue: 0.43) : accent }
    public static func background(for scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.13) : paper }
    public static let paper = Color(red: 0.985, green: 0.981, blue: 0.969)
    /// Mirrors the app's Theme green/amber/red so the widget and the window agree
    /// about what a full disk looks like, not just about the number.
    public static func tint(for pressure: StoragePressure, scheme: ColorScheme) -> Color {
        switch pressure {
        case .comfortable: return scheme == .dark ? Color(red: 0.48, green: 0.78, blue: 0.63) : Color(red: 0.22, green: 0.40, blue: 0.33)
        case .tight: return scheme == .dark ? Color(red: 0.96, green: 0.68, blue: 0.28) : Color(red: 0.65, green: 0.38, blue: 0.04)
        case .low: return scheme == .dark ? Color(red: 0.98, green: 0.47, blue: 0.42) : Color(red: 0.72, green: 0.16, blue: 0.13)
        case .unavailable: return .secondary
        }
    }
}
public func widgetBytes(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—" }

public struct StorageWidgetFace: View {
    @Environment(\.colorScheme) private var colorScheme
    public let metrics: WidgetMetrics
    public let compact: Bool
    public init(metrics: WidgetMetrics, compact: Bool) { self.metrics = metrics; self.compact = compact }
    /// The small widget has no room for a separate state label, so a concerning
    /// state is named in the caption rather than left to the bar's colour.
    private var compactCaption: String {
        let pressure = StoragePressure.evaluate(free: metrics.freeDisk ?? 0, total: metrics.totalDisk ?? 0, thresholdGB: StoragePressure.defaultThresholdGB)
        return compact && pressure.isConcerning ? "Available · " + pressure.title : "Available on this volume"
    }
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
                Text(metrics.freeDisk == nil ? "Measurement unavailable" : compactCaption).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let fraction = metrics.usedFraction {
                // Same judgement as the Cleanup page and the menu-bar popover. A
                // widget cannot read the app's preferences, so it uses the shipped
                // default threshold rather than a colour that means nothing.
                let pressure = StoragePressure.evaluate(
                    free: metrics.freeDisk ?? 0,
                    total: metrics.totalDisk ?? 0,
                    thresholdGB: StoragePressure.defaultThresholdGB
                )
                ProgressView(value: fraction)
                    .tint(WidgetPalette.tint(for: pressure, scheme: colorScheme))
                    .accessibilityLabel("Storage \(Int(fraction * 100)) percent used. \(pressure.spoken)")
                if !compact {
                    HStack(spacing: 5) {
                        Text("\(widgetBytes(metrics.totalDisk)) total · \(Int(fraction * 100))% used")
                        if pressure.isConcerning {
                            Text(pressure.title).foregroundStyle(WidgetPalette.tint(for: pressure, scheme: colorScheme))
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
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
