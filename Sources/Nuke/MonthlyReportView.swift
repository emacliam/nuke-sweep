import SwiftUI
import UserNotifications

struct MonthlyReportView: View {
    @Environment(FeatureModel.self) private var features
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MonthlyReport.notificationsKey) private var notifications = false
    @State var monthOffset: Int

    var body: some View {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .month, value: -monthOffset, to: .now) ?? .now
        let period = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        let report = MonthlyReport(period: period, checks: MonthlyCheckArchive.records(), receipts: features.receipts)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Monthly storage report").font(.system(size: 22, weight: .semibold))
                Spacer()
                Picker("Month", selection: $monthOffset) {
                    ForEach(0..<12) { offset in
                        if let month = calendar.date(byAdding: .month, value: -offset, to: .now) {
                            Text(month.formatted(.dateTime.month(.wide).year())).tag(offset)
                        }
                    }
                }.frame(width: 220)
            }
            if features.historyLoading {
                ProgressView("Loading cleanup history…")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimated space freed: \(bytes(report.freed))")
                    Text("Automatically moved to Trash: \(bytes(report.automaticMoved))")
                    Text("Based on retained receipts. Files still in Trash occupy disk space.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            Divider()
            Text("What grew").font(.system(size: 14, weight: .semibold))
            if !report.comparedChecks {
                Text("Run two comparable checks in this month to see what grew.").foregroundStyle(Theme.secondary)
            } else if report.growers.isEmpty {
                Text("No growth in locations measured by both checks.").foregroundStyle(Theme.secondary)
            } else {
                ForEach(report.growers) { item in
                    HStack {
                        Text(item.name).lineLimit(1).truncationMode(.middle).help(item.path)
                        Spacer()
                        Text("+\(bytes(item.delta))").monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
            Toggle("Notify me when a monthly report is ready", isOn: $notifications)
                .onChange(of: notifications) { _, enabled in
                    if enabled {
                        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                    }
                }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 575).frame(minHeight: 350)
    }
}
