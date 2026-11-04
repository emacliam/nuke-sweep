import SwiftUI
import AppKit
import UserNotifications
import WidgetKit

@MainActor final class LiveMonitor: ObservableObject {
    @Published var sleeping = false
    @Published var sample: MonitorSample?
    @Published var monitorPaused = false
    @Published var monitorInterval = UserDefaults.standard.object(forKey: "nuke.monitorInterval") as? Double ?? 5
    @Published var monitorHistory: [MonitorSample] = []
    @Published var showStatusName = UserDefaults.standard.bool(forKey: "nuke.statusName")
    @Published var statusBarMetric = UserDefaults.standard.string(forKey: "nuke.statusBarMetric") ?? "storage"
    @Published var monitorEnabled = UserDefaults.standard.object(forKey: "nuke.menuEnabled") as? Bool ?? true
    @Published var alertsEnabled = UserDefaults.standard.bool(forKey: "nuke.alertsEnabled")
    @Published var lowSpaceGB = UserDefaults.standard.object(forKey: "nuke.lowSpaceGB") as? Double ?? 10
    @Published var notificationNote = UserDefaults.standard.bool(forKey: "nuke.alertsEnabled") ? "Alerts are enabled subject to macOS notification permission." : "Alerts are off until you enable them."
    private var alertRequestID = UUID()
    private var lastWidgetReload = Date.distantPast
    private var monitorTimer: Timer?
    private var refreshing = false
    private var forcedRefreshPending = false
    private var sampleGeneration = UUID()
    private var previousCPU: [UInt64]?
    private var lastAlert = UserDefaults.standard.object(forKey: "nuke.lastAlert") as? Date ?? Date.distantPast
    private var highCPUSamples = 0
    func configureMonitor() {
        if ![5.0, 10.0, 30.0].contains(monitorInterval) { monitorInterval = 5 }
        UserDefaults.standard.set(monitorEnabled, forKey: "nuke.menuEnabled"); monitorTimer?.invalidate(); monitorTimer = nil
        sampleGeneration = UUID(); previousCPU = nil; highCPUSamples = 0
        if monitorEnabled && !monitorPaused && !sleeping {
            refreshMonitor()
            monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshMonitor() } }
            monitorTimer?.tolerance = monitorInterval * 0.25
        }
    }
    func sleep() { sampleGeneration = UUID(); sleeping = true; monitorTimer?.invalidate(); monitorTimer = nil; previousCPU = nil }
    func wake() { sleeping = false; configureMonitor() }
    func storageDidChange() { refreshMonitor(force: true); lastWidgetReload = Date(); WidgetCenter.shared.reloadAllTimelines() }
    func refreshMonitor(force: Bool = false) {
        if refreshing { forcedRefreshPending = forcedRefreshPending || force; return }
        guard !sleeping, !monitorPaused || force else { return }
        refreshing = true
        let generation = sampleGeneration
        Task {
            let values = await Task.detached(priority: .utility) { (ResourceMonitor.cpuTicks(), MachineService.snapshot(), ResourceMonitor.memory(), Date()) }.value
            refreshing = false
            defer { if forcedRefreshPending { forcedRefreshPending = false; refreshMonitor(force: true) } }
            guard generation == sampleGeneration, !sleeping, !monitorPaused || force else { return }
            let cpu = previousCPU.flatMap { ResourceMonitor.utilization(before: $0, after: values.0) }
            previousCPU = values.0
            sample = MonitorSample(disk: values.1, cpu: cpu, memory: values.2, date: values.3)
            recordSample(cpu: cpu)
        }
    }
    private func recordSample(cpu: Double?) {
        if let sample {
            monitorHistory.append(sample)
            monitorHistory = Array(monitorHistory.filter { sample.date.timeIntervalSince($0.date) <= 600 }.suffix(121))
        }
        if Date().timeIntervalSince(lastWidgetReload) >= 900 { lastWidgetReload = Date(); WidgetCenter.shared.reloadAllTimelines() }
        guard alertsEnabled, let sample else { return }
        highCPUSamples = (cpu ?? 0) >= 85 ? highCPUSamples + 1 : 0
        guard Date().timeIntervalSince(lastAlert) >= 3600 else { return }
        let low = sample.disk.totalDisk > 0 && sample.disk.freeDisk < Int64(lowSpaceGB * 1_000_000_000)
        guard low || highCPUSamples >= 3 else { return }; lastAlert = Date(); UserDefaults.standard.set(lastAlert, forKey: "nuke.lastAlert")
        AlertCenter.shared.post(key: low ? "storage" : "cpu", title: low ? "Storage is running low" : "Sustained CPU activity", detail: low ? "\(bytes(sample.disk.freeDisk)) available. Review the cleanup queue." : "CPU has been at least 85% for three samples. Review running processes.", enabled: alertsEnabled)
    }

    func setAlerts(_ enabled: Bool) {
        let request = UUID(); alertRequestID = request
        if !enabled { alertsEnabled = false; UserDefaults.standard.set(false, forKey: "nuke.alertsEnabled"); notificationNote = "Alerts are off."; return }
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard alertRequestID == request else { return }
                alertsEnabled = allowed; UserDefaults.standard.set(allowed, forKey: "nuke.alertsEnabled")
                notificationNote = allowed ? "Alerts enabled. At most one storage/CPU alert per hour while monitoring runs." : "Notifications were not allowed. Enable them in System Settings if you want alerts."
            } catch { guard alertRequestID == request else { return }; alertsEnabled = false; UserDefaults.standard.set(false, forKey: "nuke.alertsEnabled"); notificationNote = error.localizedDescription }
        }
    }
}
