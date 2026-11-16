import SwiftUI

struct AppLeftoversReportView: View {
    @Environment(AppModel.self) private var model
    @State private var report: InventoryReport?
    @State private var cancellation: ScanCancellation?

    var body: some View {
        DisclosureGroup("Possible app leftovers") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Look for caches, preferences, and logs whose identifiers do not match apps in the usual Applications folders. Helpers, shared services, and apps installed elsewhere may still use these files.")
                    .foregroundStyle(Theme.secondary)
                HStack {
                    Button(report == nil ? "Check for leftovers" : "Refresh leftovers") { inspect() }
                        .buttonStyle(QuietButton()).disabled(cancellation != nil)
                    if let cancellation {
                        ProgressView().controlSize(.small)
                        Button("Stop") { cancellation.cancel() }.buttonStyle(.plain)
                    }
                }
                if let report {
                    if report.entries.isEmpty { Text("No unmatched identifiers found in the locations checked.") }
                    ForEach(report.entries.sorted { $0.item.allocated > $1.item.allocated }) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.owner).fontWeight(.semibold)
                                Text(entry.item.url.path).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).truncationMode(.middle).help(entry.item.url.path)
                            }
                            Spacer()
                            Text(bytes(entry.item.allocated) + (entry.item.incomplete ? " · partial" : ""))
                                .monospacedDigit()
                            Button("Show in Finder") { model.reveal(entry.item.url) }.buttonStyle(.plain)
                        }
                    }
                    ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).foregroundStyle(Theme.secondary)
                    }
                }
            }.font(.system(size: 12)).padding(.vertical, 8)
        }.onDisappear { cancellation?.cancel() }
    }

    private func inspect() {
        let token = ScanCancellation()
        cancellation = token
        Task {
            report = await DiskWork.run("Checking possible app leftovers", cancellation: token) {
                let installed = AppInventory.apps(token: token)
                return AppInventory.leftovers(installed: installed, token: token, reportOnly: true)
            }
            cancellation = nil
        }
    }
}
