import SwiftUI
import UserNotifications

enum AlertRoute: Equatable { case storage(URL), growth(String), processes, findSpace }
struct NukeAlert: Identifiable, Codable {
    let id: UUID
    let key: String
    let date: Date
    let title: String
    let detail: String
    let root: URL?
}
@MainActor final class AlertCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()
    @Published private(set) var records: [NukeAlert] = []
    @Published private(set) var ignored = Set<String>()
    @Published private(set) var snoozed: [String: Date] = [:]
    @Published var note = ""
    weak var model: AppModel? { didSet { if let pending { self.pending = nil; review(pending) } } }
    private var pending: NukeAlert?
    private var lastSent: [String: Date] = [:]
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "nuke.alertRecords"), let records = try? JSONDecoder().decode([NukeAlert].self, from: data) { self.records = Array(records.prefix(100)) }
        ignored = Set(UserDefaults.standard.stringArray(forKey: "nuke.ignoredAlerts") ?? [])
        if let data = UserDefaults.standard.data(forKey: "nuke.snoozes"), let values = try? JSONDecoder().decode([String: Date].self, from: data) { snoozed = values }
        for record in records { lastSent[record.key] = max(lastSent[record.key] ?? .distantPast, record.date) }
    }
    func registerActions() {
        let actions = [UNNotificationAction(identifier: "review", title: "Review", options: .foreground), UNNotificationAction(identifier: "ignore", title: "Ignore", options: []), UNNotificationAction(identifier: "later", title: "Remind in an hour", options: [])]
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "nuke.alert", actions: actions, intentIdentifiers: [], options: [])])
    }
    @discardableResult func post(key: String, title: String, detail: String, root: URL? = nil, enabled: Bool) -> Bool {
        guard enabled, !ignored.contains(key), (snoozed[key] ?? .distantPast) <= Date(), Date().timeIntervalSince(lastSent[key] ?? .distantPast) >= 3600 else { return false }
        let alert = NukeAlert(id: UUID(), key: key, date: Date(), title: title, detail: detail, root: root)
        lastSent[key] = alert.date; records.insert(alert, at: 0); records = Array(records.prefix(100)); persist()
        Task { do { try await UNUserNotificationCenter.current().add(request(alert)) } catch { note = "Notification could not be delivered: " + error.localizedDescription } }
        return true
    }
    @discardableResult func recordGrowth(root: URL, before: Int64, after: Int64, enabled: Bool) -> Bool {
        guard Self.significantGrowth(before: before, after: after) else { return false }
        return post(key: "growth:" + root.standardizedFileURL.path, title: root.lastPathComponent + " grew", detail: "+" + bytes(after - before) + " since the previous complete measurement. Review what changed before cleaning.", root: root, enabled: enabled)
    }
    static func significantGrowth(before: Int64, after: Int64) -> Bool { after > before && (after - before >= 1_000_000_000 || (after - before >= 100_000_000 && Double(after - before) >= Double(max(1, before)) * 0.2)) }
    func review(_ alert: NukeAlert) {
        guard let model else { pending = alert; return }
        switch Self.route(alert, scanRoots: model.features.scans.map(\.root)) {
        case .growth(let root): UserDefaults.standard.set(root, forKey: "nuke.growthRoot"); model.scanRoot = URL(fileURLWithPath: root); model.showMainWindow(.growth)
        case .storage(let root): model.showMainWindow(.storage); model.scan(root, force: true)
        case .processes: model.showMainWindow(.processes)
        case .findSpace: model.showMainWindow(.findSpace)
        }
    }
    nonisolated static func route(_ alert: NukeAlert, scanRoots: [String]) -> AlertRoute {
        if let root = alert.root {
            if let saved = scanRoots.first(where: { URL(fileURLWithPath: $0).standardizedFileURL == root.standardizedFileURL }) { return .growth(saved) }
            return .storage(root)
        }
        return alert.key == "cpu" ? .processes : .findSpace

    }
    func ignore(_ alert: NukeAlert) { ignored.insert(alert.key); persist(); UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["remind-" + alert.key]) }
    func unignore(_ key: String) { ignored.remove(key); persist() }
    func later(_ alert: NukeAlert) {
        snoozed[alert.key] = Date().addingTimeInterval(3600); persist()
        Task {
            do { try await UNUserNotificationCenter.current().add(request(alert, reminder: true)); note = "Reminder scheduled in an hour. It refers to the original measurement." }
            catch { note = "Could not schedule reminder: " + error.localizedDescription }
        }
    }
    private func request(_ alert: NukeAlert, reminder: Bool = false) -> UNNotificationRequest {
        let content = UNMutableNotificationContent(); content.title = (reminder ? "Reminder: " : "Nuke Sweep: ") + alert.title
        content.body = alert.detail + (reminder ? " Measured " + alert.date.formatted() + "." : "")
        content.categoryIdentifier = "nuke.alert"; content.userInfo = ["alertID": alert.id.uuidString]
        return UNNotificationRequest(identifier: reminder ? "remind-" + alert.key : alert.id.uuidString, content: content, trigger: reminder ? UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false) : nil)
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: "nuke.alertRecords") }
        UserDefaults.standard.set(Array(ignored.prefix(200)), forKey: "nuke.ignoredAlerts")
        snoozed = snoozed.filter { $0.value > Date() }
        if let data = try? JSONEncoder().encode(snoozed) { UserDefaults.standard.set(data, forKey: "nuke.snoozes") }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["alertID"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            if let record = self.records.first(where: { $0.id.uuidString == id }) {
                switch action { case "ignore": self.ignore(record); case "later": self.later(record); default: self.review(record) }
            }
            completionHandler()
        }
    }
}
struct AlertsView: View {
    @ObservedObject private var alerts = AlertCenter.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Alerts use existing complete scans and your active watchlist; they do not start background folder scans. Growth needs at least 1 GB, or 100 MB and 20%. Delivery requires optional alerts and macOS permission.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            if alerts.records.isEmpty { EmptyPanel(symbol: "bell", title: "Nothing needs attention yet", detail: "Storage, sustained CPU, and significant measured folder growth will appear here when alerts are enabled. No historical changes are invented.") }
            ForEach(alerts.records) { alert in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(alert.title).fontWeight(.semibold); Spacer(); Text(alert.date.formatted()).foregroundStyle(Theme.secondary) }.font(.system(size: 12))
                    Text(alert.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if let root = alert.root { Text(root.path).font(.system(size: 10)).textSelection(.enabled) }
                    HStack {
                        Button("Review") { alerts.review(alert) }.buttonStyle(QuietButton())
                        Button(alerts.ignored.contains(alert.key) ? "Unignore" : "Ignore") { if alerts.ignored.contains(alert.key) { alerts.unignore(alert.key) } else { alerts.ignore(alert) } }.buttonStyle(QuietButton())
                        Button("Remind in an hour") { alerts.later(alert) }.buttonStyle(QuietButton())
                        if let until = alerts.snoozed[alert.key], until > Date() { Text("Snoozed until " + until.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }
                }.padding(.vertical, 12); Divider()
            }
            if !alerts.note.isEmpty { Notice(text: alerts.note, symbol: "info.circle") }
        }
    }
}
