import Foundation
import UserNotifications

enum ScanFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case hourly
    case daily
    case weekly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
    var interval: TimeInterval {
        switch self {
        case .hourly: return 3_600
        case .daily: return 86_400
        case .weekly: return 604_800
        }
    }
    func next(after date: Date) -> Date { date.addingTimeInterval(interval) }
}

struct ScanQuietHours: Codable, Equatable, Sendable {
    var enabled = false
    var startMinute = 22 * 60
    var endMinute = 7 * 60

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        guard startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}

struct ScheduledScan: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var path: String
    var frequency: ScanFrequency
    var enabled = true
    var lastRun: Date?
    var nextRun: Date
    var lastResult: String?

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Runs folder measurements while Nuke Sweep is open. It never selects or deletes anything;
/// completed measurements go through FeatureModel.saveScan and therefore the existing Growth
/// history and alert path.
@Observable @MainActor final class ScheduledScanStore {
    private static let defaultsKey = "nuke.scheduledScans"
    private(set) var scans: [ScheduledScan] = []
    private(set) var runningID: UUID?
    private(set) var note: String?
    var quietHours = ScanQuietHours() { didSet { persistQuietHours() } }
    var notificationsEnabled = false { didSet { defaults.set(notificationsEnabled, forKey: "nuke.scheduledNotifications") } }
    /// Returns an optional sentence about what changed, for the notification.
    var onScan: ((URL, ScanResult) -> String?)?

    private var timer: Timer?
    private var paused = false
    private var token: ScanCancellation?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([ScheduledScan].self, from: data) {
            scans = decoded
        }
        if let data = defaults.data(forKey: "nuke.scheduledQuietHours"),
           let decoded = try? JSONDecoder().decode(ScanQuietHours.self, from: data) {
            quietHours = decoded
        }
        notificationsEnabled = defaults.bool(forKey: "nuke.scheduledNotifications")
    }

    func setQuietHoursEnabled(_ enabled: Bool) { quietHours.enabled = enabled }
    func setQuietTime(_ kind: WritableKeyPath<ScanQuietHours, Int>, minute: Int) { quietHours[keyPath: kind] = max(0, min(1_439, minute)) }
    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        guard enabled else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func start() {
        guard timer == nil, !paused else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkDue()
    }

    func pause() {
        paused = true
        timer?.invalidate(); timer = nil
        token?.cancel(); token = nil
        runningID = nil
        note = "Scheduled scans pause while Nuke Sweep sleeps or is closed."
    }

    func resume() {
        guard paused else { return }
        paused = false
        start()
    }

    @discardableResult
    func add(_ url: URL, frequency: ScanFrequency) -> UUID {
        let standardized = url.standardizedFileURL
        if let existing = scans.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == standardized }) {
            update(existing.id) { $0.frequency = frequency; $0.enabled = true }
            return existing.id
        }
        let schedule = ScheduledScan(path: standardized.path, frequency: frequency, nextRun: Date().addingTimeInterval(frequency.interval))
        scans.append(schedule)
        persist()
        note = "Scheduled \(standardized.lastPathComponent) \(frequency.title.lowercased()). Runs only while Nuke Sweep is open."
        return schedule.id
    }

    func remove(_ id: UUID) {
        if runningID == id { cancelRunning() }
        scans.removeAll { $0.id == id }
        persist()
    }

    func toggle(_ id: UUID, enabled: Bool) {
        update(id) { $0.enabled = enabled }
    }

    func setFrequency(_ id: UUID, frequency: ScanFrequency) {
        update(id) { scan in
            scan.frequency = frequency
            let base = scan.lastRun ?? Date()
            scan.nextRun = frequency.next(after: base)
        }
    }

    func runNow(_ id: UUID) {
        guard runningID == nil, let schedule = scans.first(where: { $0.id == id }) else { return }
        run(schedule)
    }

    func cancelRunning() {
        token?.cancel(); token = nil
        runningID = nil
        note = "Scheduled scan cancelled. Nothing was changed."
    }

    private func checkDue(now: Date = Date()) {
        guard !paused, runningID == nil else { return }
        guard !quietHours.contains(now) else {
            note = "Quiet hours: scheduled scans wait until the window ends."
            return
        }
        guard let due = scans.first(where: { $0.enabled && $0.nextRun <= now }) else { return }
        run(due)
    }

    private func run(_ schedule: ScheduledScan) {
        guard runningID == nil else { return }
        let id = schedule.id
        let url = schedule.url
        let token = ScanCancellation()
        self.token = token
        runningID = id
        note = "Scheduled scan running: \(schedule.name)"
        Task {
            let result = await DiskWork.run("Scheduled scan: \(schedule.name)", priority: .background, cancellation: token) {
                DiskScanner.scan(url, cancellation: token, limit: 60_000, deadline: Date().addingTimeInterval(30))
            }
            guard runningID == id else { return }
            self.token = nil
            runningID = nil
            let digest = onScan?(url, result) ?? nil
            update(id) { scan in
                scan.lastRun = Date()
                scan.nextRun = scan.frequency.next(after: Date())
                if result.limited || result.skipped > 0 {
                    scan.lastResult = "Partial: \(result.items.count) items, \(result.skipped) skipped. History not saved."
                } else {
                    scan.lastResult = "\(result.items.count) items · \(bytes(result.logical))"
                }
            }
            // Name the largest thing found, so the notification carries a finding
            // rather than only a status. Nothing is selected or cleaned by this.
            let largest = result.items.max { $0.size < $1.size }
            let headline = largest.map { " Largest: \($0.name) at \(bytes($0.size))." } ?? ""
            let message = result.limited || result.skipped > 0
                ? "Scheduled scan of \(schedule.name) was partial. Review access before relying on it."
                : "Scheduled scan of \(schedule.name) finished: \(bytes(result.logical))." + (digest.map { " " + $0 } ?? headline) + " No cleanup ran."
            note = message
            notify(message, schedule: schedule)
        }
    }

    private func notify(_ message: String, schedule: ScheduledScan) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Scheduled scan finished"
        content.body = message
        let request = UNNotificationRequest(identifier: "scan-" + schedule.id.uuidString + "-" + UUID().uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func update(_ id: UUID, _ mutate: (inout ScheduledScan) -> Void) {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { return }
        mutate(&scans[index])
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func persistQuietHours() {
        guard let data = try? JSONEncoder().encode(quietHours) else { return }
        defaults.set(data, forKey: "nuke.scheduledQuietHours")
    }
}
