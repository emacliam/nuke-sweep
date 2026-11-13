import SwiftUI
import NukeWidgetUI

enum StatusBarMetric: String, CaseIterable, Identifiable {
    case storage, cpu, memory, icon
    var id: String { rawValue }
    var title: String {
        switch self { case .storage: return "Available storage"; case .cpu: return "CPU activity"; case .memory: return "VM memory estimate"; case .icon: return "Icon only" }
    }
    func reading(_ sample: MonitorSample?) -> String? {
        switch self {
        case .storage:
            guard let sample else { return "Measuring…" }
            return sample.disk.totalDisk > 0 ? bytes(sample.disk.freeDisk) + " free" : "Storage —"
        case .cpu: return sample?.cpu.map { String(format: "CPU %.0f%%", $0) } ?? "CPU —"
        case .memory: return sample?.memory.map { bytes($0) + " VM" } ?? "VM —"
        case .icon: return nil
        }
    }
}
struct NukeStatusBarLabel: View {
    @Environment(LiveMonitor.self) var monitor
    private var mode: StatusBarMetric { StatusBarMetric(rawValue: monitor.statusBarMetric) ?? .storage }
    var body: some View {
        HStack(spacing: 4) {
            SweepMark(monochrome: true).frame(width: 16, height: 14)
            if let reading = monitor.monitorPaused ? "Paused" : mode.reading(monitor.sample) { Text("Nuke Sweep").fontWeight(.medium); Text(reading).monospacedDigit() }
        }.font(.system(size: 11))
        .accessibilityLabel("Nuke Sweep. " + (monitor.monitorPaused ? "Monitoring paused" : (mode.reading(monitor.sample) ?? "Open monitor")))
        .help("Nuke Sweep — click for storage, CPU, and memory")
    }
}
