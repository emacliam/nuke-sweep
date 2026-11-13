import Foundation
import Darwin

public struct WidgetMetrics: Codable, Equatable, Sendable {
    public let date: Date
    public let totalDisk: Int64?
    public let freeDisk: Int64?
    public let cpu: Double?
    public let memory: Int64?
    public let physicalMemory: Int64
    public init(date: Date = Date(), totalDisk: Int64?, freeDisk: Int64?, cpu: Double?, memory: Int64?, physicalMemory: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)) {
        self.date = date; self.totalDisk = totalDisk; self.freeDisk = freeDisk; self.cpu = cpu; self.memory = memory; self.physicalMemory = physicalMemory
    }
    public static var placeholder: WidgetMetrics { .init(totalDisk: nil, freeDisk: nil, cpu: nil, memory: nil) }
    public var usedFraction: Double? {
        guard let totalDisk, let freeDisk, totalDisk > 0 else { return nil }
        return min(1, max(0, (Double(totalDisk) - Double(freeDisk)) / Double(totalDisk)))
    }
}
public enum SystemMetrics {
    public static func storage(path: String = FileManager.default.homeDirectoryForCurrentUser.path) throws -> (total: Int64, free: Int64) {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
        guard let total = (attrs[.systemSize] as? NSNumber)?.int64Value, let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value else { throw CocoaError(.fileReadUnknown) }
        return (total, free)
    }
    public static func cpuTicks() -> [UInt64] {
        var info = host_cpu_load_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        guard status == KERN_SUCCESS else { return [] }
        return [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
    }
    public static func utilization(before: [UInt64], after: [UInt64]) -> Double? {
        guard before.count == 4, after.count == 4, (before + after).allSatisfy({ $0 <= UInt64(UInt32.max) }) else { return nil }
        let delta = zip(before, after).map { old, new in new >= old ? new - old : (UInt64(UInt32.max) - old) + new + 1 }
        let total = delta.reduce(0, +); guard total > 0 else { return nil }
        return Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total) * 100
    }
    public static func memory() -> Int64? {
        var info = vm_statistics64_data_t(), count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        guard status == KERN_SUCCESS else { return nil }
        return (Int64(info.active_count) + Int64(info.wire_count) + Int64(info.compressor_page_count)) * pageSize()
    }

    /// Darwin exposes the kernel page size as a mutable global (`vm_kernel_page_size`),
    /// which Swift 6 cannot prove is safe to read concurrently. `host_page_size` is the
    /// same value through a function call with no shared mutable state, so the page
    /// count above can be scaled without an unsafe opt-out.
    private static func pageSize() -> Int64 {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS, size > 0 else { return 4096 }
        return Int64(size)
    }
    public static func snapshot(cpu: Double? = nil) -> WidgetMetrics {
        let disk = try? storage()
        return .init(totalDisk: disk?.total, freeDisk: disk?.free, cpu: cpu, memory: memory())
    }
}

/// How much trouble a volume is actually in.
///
/// Lives here, not in the app, because three surfaces render it — the Cleanup
/// page, the menu-bar popover and the desktop widget — and they must not be able
/// to disagree. Colour mapping stays with each surface's own palette; only the
/// judgement is shared.
public enum StoragePressure: String, Equatable, Sendable {
    case comfortable, tight, low, unavailable

    /// A volume is under pressure for two independent reasons, and either can
    /// raise the state.
    ///
    /// Absolute headroom is the user's own low-space alert threshold, so the bar
    /// agrees with the notification they configured. Proportional fullness counts
    /// separately: 20 GB free on a 500 GB disk clears a 10 GB threshold while
    /// still being 96% full, and calling that "comfortable" in a cleanup utility
    /// would be wrong. The proportional rule can only hold a state back, never
    /// soften one the user's own threshold has already called low.
    public static func evaluate(free: Int64, total: Int64, thresholdGB: Double) -> StoragePressure {
        guard total > 0, free >= 0 else { return .unavailable }
        let threshold = Int64(max(1, thresholdGB) * 1_000_000_000)
        if free <= threshold { return .low }
        if free <= threshold * 2 { return .tight }
        let usedFraction = Double(max(0, total - free)) / Double(total)
        return usedFraction >= 0.9 ? .tight : .comfortable
    }

    /// The default the app ships with, so a widget that cannot read the app's
    /// preferences still judges the disk the same way out of the box.
    public static let defaultThresholdGB: Double = 10

    public var isConcerning: Bool { self == .tight || self == .low }

    /// Never the only carrier of the state: every surface pairs this with colour.
    public var title: String {
        switch self {
        case .comfortable: return String(localized: "Comfortable")
        case .tight: return String(localized: "Getting tight")
        case .low: return String(localized: "Low")
        case .unavailable: return String(localized: "Unavailable")
        }
    }

    public var spoken: String {
        switch self {
        case .comfortable: return String(localized: "Storage is comfortable")
        case .tight: return String(localized: "Storage is getting tight")
        case .low: return String(localized: "Storage is low")
        case .unavailable: return String(localized: "Storage reading unavailable")
        }
    }
}
