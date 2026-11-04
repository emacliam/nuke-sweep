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
        return (Int64(info.active_count) + Int64(info.wire_count) + Int64(info.compressor_page_count)) * Int64(vm_kernel_page_size)
    }
    public static func snapshot(cpu: Double? = nil) -> WidgetMetrics {
        let disk = try? storage()
        return .init(totalDisk: disk?.total, freeDisk: disk?.free, cpu: cpu, memory: memory())
    }
}
