import SwiftUI

struct FailureReportPreview: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FailureReport.enabledKey) private var enabled = false
    let report: FailureReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review failure report").font(.system(size: 20, weight: .semibold))
            Text("This is the complete report. Choose where to share it.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            ScrollView {
                Text(verbatim: report.json)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if enabled {
                    ShareLink(item: report.json, subject: Text("Nuke Sweep failure report")) {
                        Label("Share report…", systemImage: "square.and.arrow.up")
                    }.buttonStyle(PrimaryButton())
                }
            }
        }.padding(24).frame(width: 540, height: 330)
    }
}
