import SwiftUI
import UniformTypeIdentifiers
import NukeMetrics
import NukeWidgetUI
import AppKit

struct MonitorPopover: View {
    @Environment(LiveMonitor.self) var monitor
    @Environment(AppModel.self) var model
    @AppStorage("nuke.appearance") private var appearance = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) { SweepMark().frame(width: 22, height: 19); Text("Nuke Sweep") }.font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(monitor.sleeping ? "Sleeping" : monitor.monitorPaused ? "Paused" : "Live").font(.system(size: 10, weight: .medium)).foregroundStyle(monitor.monitorPaused ? Theme.secondary : Theme.green)
                Button { monitor.monitorPaused.toggle(); monitor.configureMonitor() } label: { Image(systemName: monitor.monitorPaused ? "play.fill" : "pause.fill").frame(width: 22, height: 22) }.buttonStyle(.plain).accessibilityLabel(monitor.monitorPaused ? "Resume monitoring" : "Pause monitoring")
                Button { monitor.refreshMonitor() } label: { Image(systemName: "arrow.clockwise").frame(width: 22, height: 22) }.buttonStyle(.plain).disabled(monitor.monitorPaused || monitor.sleeping).help("Refresh measurements").accessibilityLabel("Refresh monitor measurements")
            }
            if let sample = monitor.sample {
                storageSection(sample)
                HStack(alignment: .top, spacing: 22) {
                    metric("CPU", value: sample.cpu.map { String(format: "%.1f%%", $0) } ?? "Measuring…")
                    Rectangle().fill(Theme.line).frame(width: 1, height: 36)
                    metric("VM MEMORY", value: sample.memory.map(bytes) ?? "Unavailable")
                }
                HStack { Text("Updated " + sample.date.formatted(date: .omitted, time: .standard)); Spacer(); Text("Every \(Int(monitor.monitorInterval))s") }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else { Text("Collecting measurements…").font(.system(size: 12)) }
            if !monitor.monitorHistory.isEmpty {
                MenuCPUChart(interval: monitor.monitorInterval, samples: Array(monitor.monitorHistory.suffix(25)))
            }
            if let receipt = model.features.receipts.first { LastCleanupNote(receipt: receipt, compact: true) }
            if monitor.monitorPaused || monitor.sleeping { Text("Readings are the last measurements; sampling is suspended.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("VM memory is active + wired + compressed, not memory pressure.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            // The menu-bar item earns its place as the way into a cleanup, so its
            // primary action starts one rather than opening a page to start from.
            HStack(spacing: 8) {
                Button("Check this Mac") { model.showMainWindow(.findSpace); model.startFullCheck() }
                    .buttonStyle(PrimaryButton()).disabled(model.fullCheck.running || model.actionBusy)
                Button("Developer caches") { model.showMainWindow(.developer) }.buttonStyle(QuietButton())
                Spacer()
            }
            HStack { Button("Open Nuke Sweep") { model.showMainWindow() }; Spacer(); Button { model.showMainWindow(.monitor) } label: { Image(systemName: "gearshape") }.accessibilityLabel("Monitor & alert settings"); Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.accessibilityLabel("Quit Nuke Sweep") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.padding(20).frame(width: 330).background(Theme.paper).foregroundStyle(Theme.ink)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onAppear { if !monitor.monitorPaused { monitor.refreshMonitor() } }
    }
    private func storageSection(_ sample: MonitorSample) -> some View {
        let pressure = StoragePressure.evaluate(free: sample.disk.freeDisk, total: sample.disk.totalDisk, thresholdGB: monitor.lowSpaceGB)
        let free: String = sample.disk.totalDisk > 0 ? bytes(sample.disk.freeDisk) : String(localized: "Unavailable")
        let capacity: String = bytes(sample.disk.totalDisk)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("AVAILABLE STORAGE").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.secondary)
                Spacer()
                if pressure != .unavailable {
                    // Paired with the colour so the state never depends on hue alone.
                    Text(pressure.label)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(pressure.tint)
                        .background(pressure.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: free).font(.system(size: 29, weight: .semibold)).monospacedDigit()
                Spacer()
                if sample.disk.totalDisk > 0 {
                    Text("of \(capacity)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            if sample.disk.totalDisk > 0 {
                ProgressView(value: Double(max(0, sample.disk.totalDisk - sample.disk.freeDisk)), total: Double(sample.disk.totalDisk))
                    .tint(pressure.tint)
            }
            if pressure == .low {
                Text("Below your \(Int(monitor.lowSpaceGB)) GB alert threshold.")
                    .font(.system(size: 10)).foregroundStyle(Theme.error)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pressure.spoken + ". " + free + " available of " + capacity)
    }

    func metric(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.secondary); Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct MonitorSettingsView: View {
    @Environment(AppModel.self) var model
    @Environment(LiveMonitor.self) var monitor
    @State private var settings = PermissionSettings()
    @AppStorage("nuke.appearance") private var appearance = "system"
    @AppStorage("nuke.hangDiagnostics") private var hangDiagnostics = false
    @Environment(FeatureModel.self) var features
    @Environment(AISettings.self) var ai
    @Environment(ScheduledScanStore.self) var scheduled
    @State private var diagnosticsNote = ""
    var body: some View {
        @Bindable var monitor = monitor
        VStack(alignment: .leading, spacing: 22) {
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented).frame(maxWidth: 320)
                    Text("Applies to the main window and the menu-bar tool.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Toggle("Capture hang diagnostics", isOn: $hangDiagnostics)
                        .font(.system(size: 13, weight: .medium))
                        .onChange(of: hangDiagnostics) { _, enabled in HangWatchdog.setEnabled(enabled) }
                    Text("Off by default. Writes a local sample and metadata if the main thread stalls for two seconds. No upload.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    HStack(spacing: 8) {
                        Button("Open diagnostics folder") { HangWatchdog.openFolder() }.buttonStyle(QuietButton())
                        Button("Open macOS crash reports") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/DiagnosticReports")) }.buttonStyle(QuietButton())
                        Button("Export diagnostics…") { exportDiagnostics() }.buttonStyle(QuietButton())
                    }
                    if !diagnosticsNote.isEmpty { Text(diagnosticsNote).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
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
                    Toggle("Optional low-storage and growth alerts", isOn: Binding(get: { monitor.alertsEnabled }, set: { monitor.setAlerts($0) })).font(.system(size: 13, weight: .medium)).disabled(!monitor.monitorEnabled)
                    Stepper("Low storage threshold: \(Int(monitor.lowSpaceGB)) GB", value: $monitor.lowSpaceGB, in: 1...100, step: 1).font(.system(size: 12)).onChange(of: monitor.lowSpaceGB) { _, value in UserDefaults.standard.set(value, forKey: "nuke.lowSpaceGB") }
                    Text(monitor.notificationNote).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("Enabling alerts asks macOS for notification permission. At most one low-storage alert is sent per hour, after a check that says what grew. Alerts never clean anything.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
        }.onAppear { settings.refresh() }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Nuke-Sweep-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsExporter.json(model: model, features: features, ai: ai, scheduled: scheduled).write(to: url, options: .atomic)
            diagnosticsNote = "Exported. No keys, absolute paths or file contents are included."
        } catch {
            diagnosticsNote = "Diagnostics export failed: " + error.localizedDescription
        }
    }
}
