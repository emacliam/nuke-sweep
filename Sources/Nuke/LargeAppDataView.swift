import SwiftUI

struct LargeAppDataView: View {
    @State private var expanded = false
    @State private var groups: [LargeAppData.Group] = []
    @State private var token: ScanCancellation?

    var body: some View {
        DisclosureGroup("Large app data", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("See disk space used in common app locations. Manage the data in the app that owns it.")
                    .foregroundStyle(Theme.secondary)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(group.name).fontWeight(.semibold)
                            Spacer()
                            Text(sizeLabel(group)).monospacedDigit()
                        }
                        Text(group.guidance).foregroundStyle(Theme.secondary)
                    }
                }
                if let token {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Measuring app data…")
                        Button("Stop") { token.cancel() }.buttonStyle(QuietButton())
                    }
                } else {
                    Button(groups.isEmpty ? "Measure app data" : "Refresh app data") { inspect() }
                        .buttonStyle(QuietButton())
                }
            }.font(.system(size: 12)).padding(.vertical, 8)
        }.onDisappear { token?.cancel() }
    }

    private func sizeLabel(_ group: LargeAppData.Group) -> String {
        if let size = group.bytes { return bytes(size) + (group.partial ? " · partial" : "") }
        return group.partial ? "Unavailable" : "No default location found"
    }

    private func inspect() {
        let cancellation = ScanCancellation()
        token = cancellation
        Task {
            groups = await DiskWork.run("Measuring large app data", cancellation: cancellation) {
                LargeAppData.inspect(token: cancellation)
            }
            token = nil
        }
    }
}
