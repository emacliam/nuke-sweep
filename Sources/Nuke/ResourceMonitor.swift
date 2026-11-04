import Foundation
import NukeMetrics

enum ResourceMonitor {
    static func cpuTicks() -> [UInt64] { SystemMetrics.cpuTicks() }
    static func utilization(before: [UInt64], after: [UInt64]) -> Double? { SystemMetrics.utilization(before: before, after: after) }
    static func memory() -> Int64? { SystemMetrics.memory() }
}
