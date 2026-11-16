import Foundation

enum MonthlyCheckArchive {
    private static let key = "nuke.monthlyCheckArchive"

    static func records(defaults: UserDefaults = .standard) -> [FullCheckRecord] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([FullCheckRecord].self, from: $0) } ?? []
    }

    static func append(_ record: FullCheckRecord, previous: FullCheckRecord?, defaults: UserDefaults = .standard,
                       calendar: Calendar = .current) {
        var values = records(defaults: defaults)
        if values.isEmpty, let previous { values.append(previous) }
        values.append(record)
        // Keep the first and latest check of each month for each scan coverage.
        // Many manual checks cannot crowd out earlier months.
        let cutoff = calendar.date(byAdding: .month, value: -12, to: record.date) ?? record.date
        let grouped = Dictionary(grouping: values.filter { $0.date >= cutoff }) { value in
            ArchiveGroup(month: calendar.dateInterval(of: .month, for: value.date)?.start ?? value.date,
                         projects: value.measuredProjects, coverage: value.coverage,
                         partial: value.partial, projectPath: value.projectPath)
        }
        let endpoints = grouped.values.flatMap { checks -> [FullCheckRecord] in
            let ordered = checks.sorted { $0.date < $1.date }
            return ordered.count == 1 ? ordered : [ordered[0], ordered[ordered.count - 1]]
        }.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(endpoints) { defaults.set(data, forKey: key) }
    }

    private struct ArchiveGroup: Hashable {
        let month: Date
        let projects: Bool?
        let coverage: Int?
        let partial: Bool?
        let projectPath: String?
    }
}

struct MonthlyReport {
    static let notificationKey = "monthly-report"
    static let notificationsKey = "nuke.monthlyReportNotifications"
    static let lastNotificationKey = "nuke.lastMonthlyReport"

    let period: DateInterval
    let freed: Int64
    let automaticMoved: Int64
    let growers: [FullCheckGrower]
    let comparedChecks: Bool
    let receiptCount: Int

    init(period: DateInterval, checks: [FullCheckRecord], receipts: [CleanupReceipt]) {
        self.period = period
        let monthlyReceipts = receipts.filter { $0.date >= period.start && $0.date < period.end }
        receiptCount = monthlyReceipts.count
        freed = Self.sum(monthlyReceipts.lazy.map(CleanupHistory.credit))
        automaticMoved = Self.sum(monthlyReceipts.lazy.filter { $0.title == "Automatic cleanup" }
            .flatMap(\.items).filter { $0.success && $0.trashPath != nil }.map(\.size))

        let measured = checks.filter { $0.date >= period.start && $0.date < period.end && $0.sizes != nil && $0.partial != true }
        if let latest = measured.max(by: { $0.date < $1.date }),
           let baseline = measured.filter({
               $0.date < latest.date && $0.isComparable(to: latest)
           }).min(by: { $0.date < $1.date }),
           let before = baseline.sizes, let after = latest.sizes {
            comparedChecks = true
            growers = after.compactMap { path, size -> FullCheckGrower? in
                guard let old = before[path], old >= 0, size > old else { return nil }
                return FullCheckGrower(path: path, delta: size - old, isNew: false)
            }.sorted { ($0.delta, $0.path) > ($1.delta, $1.path) }.prefix(8).map { $0 }
        } else {
            comparedChecks = false
            growers = []
        }
    }

    private static func sum(_ values: some Sequence<Int64>) -> Int64 {
        values.reduce(0) { $0 + min(max(0, $1), Int64.max - $0) }
    }
}

extension AppModel {
    func postMonthlyReportIfDue(now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: MonthlyReport.notificationsKey),
              !ProcessInfo.processInfo.arguments.contains("--demo-fixtures"),
              !features.historyLoading,
              let current = Calendar.current.dateInterval(of: .month, for: now),
              let period = Calendar.current.dateInterval(of: .month, for: current.start.addingTimeInterval(-1)),
              defaults.object(forKey: MonthlyReport.lastNotificationKey) as? Date != period.start else { return }
        let report = MonthlyReport(period: period, checks: MonthlyCheckArchive.records(), receipts: features.receipts)
        guard report.receiptCount > 0 || report.comparedChecks else { return }
        var detail = String(format: String(localized: "Estimated space freed: %@. Automatically moved to Trash: %@."),
                            bytes(report.freed), bytes(report.automaticMoved))
        if let largest = report.growers.first {
            detail += " " + String(format: String(localized: "Largest measured increase: %@."), bytes(largest.delta))
        }
        if AlertCenter.shared.post(key: MonthlyReport.notificationKey, title: String(localized: "Your monthly storage report"),
                                   detail: detail, enabled: true) {
            defaults.set(period.start, forKey: MonthlyReport.lastNotificationKey)
        }
    }
}
