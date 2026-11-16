import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nuke.onboardingStep") private var step = 1
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(format: String(localized: "Step %lld of 3"), Int64(step)))
                .font(.subheadline).foregroundStyle(Theme.secondary)
            switch step {
            case 1:
                heading("Find space on your Mac")
                Text("Nuke Sweep finds caches, project build output, and large personal files. See what takes up space and review items before moving them to Trash.")
            case 2:
                heading("Full Disk Access")
                if model.diskAccess == .granted {
                    Label("Full Disk Access appears to be enabled.", systemImage: "checkmark.circle")
                } else {
                    Text("You can continue with a more limited scan.")
                    AccessStep()
                }
            default:
                heading("Run your first check")
                Text("Your results will appear in Cleanup. You can stop the scan at any time and review what it found before choosing what to move.")
            }
            HStack {
                if step > 1 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step == 3 {
                    Button("Finish without checking", action: finish)
                    Button("Check this Mac") {
                        guard model.fullCheck.running || model.startFullCheck() else { return }
                        model.page = .findSpace
                        finish()
                    }
                    .disabled(!model.fullCheck.running && !model.canStartFullCheck)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip setup", action: finish)
                    Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 540)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .onAppear { model.refreshDiskAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDiskAccess()
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title).accessibilityAddTraits(.isHeader)
    }
}
