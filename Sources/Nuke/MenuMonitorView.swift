import SwiftUI
import NukeWidgetUI
import AppKit

struct MonitorPopover: View {
    @EnvironmentObject var monitor: LiveMonitor
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) { SweepMark().frame(width: 22, height: 19); Text("Nuke Sweep") }.font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(monitor.sleeping ? "Sleeping" : monitor.monitorPaused ? "Paused" : "Live").font(.system(size: 10, weight: .medium)).foregroundStyle(monitor.monitorPaused ? Theme.secondary : Theme.green)
                Button { monitor.monitorPaused.toggle(); monitor.configureMonitor() } label: { Image(systemName: monitor.monitorPaused ? "play.fill" : "pause.fill").frame(width: 22, height: 22) }.buttonStyle(.plain).accessibilityLabel(monitor.monitorPaused ? "Resume monitoring" : "Pause monitoring")
                Button { monitor.refreshMonitor() } label: { Image(systemName: "arrow.clockwise").frame(width: 22, height: 22) }.buttonStyle(.plain).disabled(monitor.monitorPaused || monitor.sleeping).help("Refresh measurements")
            }
            if let sample = monitor.sample {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AVAILABLE STORAGE").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.secondary)
                    HStack(alignment: .firstTextBaseline) { Text(sample.disk.totalDisk > 0 ? bytes(sample.disk.freeDisk) : "Unavailable").font(.system(size: 29, weight: .semibold)).monospacedDigit(); Spacer(); if sample.disk.totalDisk > 0 { Text("of " + bytes(sample.disk.totalDisk)).font(.system(size: 11)).foregroundStyle(Theme.secondary) } }
                    if sample.disk.totalDisk > 0 { ProgressView(value: Double(max(0, sample.disk.totalDisk - sample.disk.freeDisk)), total: Double(sample.disk.totalDisk)).tint(Theme.orange).accessibilityLabel("Storage used") }
                }
                HStack(alignment: .top, spacing: 22) {
                    metric("CPU", value: sample.cpu.map { String(format: "%.1f%%", $0) } ?? "Measuring…")
                    Rectangle().fill(Theme.line).frame(width: 1, height: 36)
                    metric("VM MEMORY", value: sample.memory.map(bytes) ?? "Unavailable")
                }
                HStack { Text("Updated " + sample.date.formatted(date: .omitted, time: .standard)); Spacer(); Text("Every \(Int(monitor.monitorInterval))s") }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else { Text("Collecting measurements…").font(.system(size: 12)) }
            if !monitor.monitorHistory.isEmpty { MenuCPUChart(interval: monitor.monitorInterval, samples: Array(monitor.monitorHistory.suffix(25))) }
            if let receipt = model.features.receipts.first { LastCleanupNote(receipt: receipt, compact: true) }
            if monitor.monitorPaused || monitor.sleeping { Text("Readings are the last measurements; sampling is suspended.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("VM memory is active + wired + compressed, not memory pressure.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 8) { Button("Find space") { model.showMainWindow(.findSpace) }.buttonStyle(PrimaryButton()); Button("Processes") { model.showMainWindow(.processes) }.buttonStyle(QuietButton()); Button("Scopes") { model.showMainWindow(.developer) }.buttonStyle(QuietButton()); Spacer() }
            HStack { Button("Open Nuke Sweep") { model.showMainWindow() }; Spacer(); Button { model.showMainWindow(.monitor) } label: { Image(systemName: "gearshape") }.accessibilityLabel("Monitor & alert settings"); Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.accessibilityLabel("Quit Nuke Sweep") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.padding(20).frame(width: 330).background(Theme.paper).foregroundStyle(Theme.ink).onAppear { if !monitor.monitorPaused { monitor.refreshMonitor() } }
    }
    func metric(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.secondary); Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct MonitorSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var monitor: LiveMonitor
    @StateObject private var settings = PermissionSettings()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Show Nuke Sweep in the menu bar", isOn: Binding(get: { monitor.monitorEnabled }, set: { monitor.monitorEnabled = $0; monitor.configureMonitor() })).font(.system(size: 14, weight: .medium))
                    Button("Open menu-bar tool") { model.statusController?.show() }.buttonStyle(QuietButton()).disabled(!monitor.monitorEnabled)
                    Picker("Status-bar reading", selection: $monitor.statusBarMetric) { ForEach(StatusBarMetric.allCases) { option in Text(option.title).tag(option.rawValue) } }.onChange(of: monitor.statusBarMetric) { _, value in UserDefaults.standard.set(value, forKey: "nuke.statusBarMetric") }
                    Toggle("Show Nuke Sweep’s name beside the reading", isOn: $monitor.showStatusName).onChange(of: monitor.showStatusName) { _, value in UserDefaults.standard.set(value, forKey: "nuke.statusName") }
                    Text("The compact status item shows the icon and selected reading. Choose Icon only for the smallest footprint.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Picker("Sample interval", selection: $monitor.monitorInterval) { Text("5 seconds").tag(5.0); Text("10 seconds").tag(10.0); Text("30 seconds").tag(30.0) }.onChange(of: monitor.monitorInterval) { _, value in UserDefaults.standard.set(value, forKey: "nuke.monitorInterval"); monitor.configureMonitor() }
                    Toggle("Launch Nuke Sweep at login", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) }))
                    Text("Login item: " + settings.loginStatus).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if !settings.note.isEmpty { Text(settings.note).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                    Text(monitor.sleeping ? "Monitoring is suspended for sleep." : monitor.monitorPaused ? "Monitoring is paused." : "Monitoring is active.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("Samples storage, CPU counters, and VM memory at the selected interval. Closing the window keeps Nuke Sweep running while the menu-bar monitor is enabled; use Quit Nuke Sweep to stop it.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if let sample = monitor.sample {
                        Text("\(bytes(sample.disk.freeDisk)) available · CPU \(sample.cpu.map { String(format: "%.1f%%", $0) } ?? "measuring") · \(sample.memory.map(bytes) ?? "unknown") active/wired/compressed").font(.system(size: 12)).monospacedDigit()
                        Text("Last sampled \(sample.date.formatted(date: .omitted, time: .standard)). Memory is not a pressure rating.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            DisclosureGroup("Recent resource history") { ResourceHistoryChart(samples: monitor.monitorHistory, interval: monitor.monitorInterval) }.font(.system(size: 12))
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Optional storage and sustained-CPU alerts", isOn: Binding(get: { monitor.alertsEnabled }, set: { monitor.setAlerts($0) })).font(.system(size: 13, weight: .medium)).disabled(!monitor.monitorEnabled)
                    Stepper("Low storage threshold: \(Int(monitor.lowSpaceGB)) GB", value: $monitor.lowSpaceGB, in: 1...100, step: 1).font(.system(size: 12)).onChange(of: monitor.lowSpaceGB) { _, value in UserDefaults.standard.set(value, forKey: "nuke.lowSpaceGB") }
                    Text(monitor.notificationNote).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("Enabling alerts asks macOS for notification permission. CPU alerts require three consecutive samples at or above 85% (duration depends on the sample interval). At most one alert is sent per hour. Nothing is automatically cleaned.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }.onAppear { settings.refresh() }
    }
}
