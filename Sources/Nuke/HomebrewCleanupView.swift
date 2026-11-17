import SwiftUI

private enum HomebrewCleanup {
    static func executable() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    static func candidates(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("Would remove: ") }
            .map(String.init)
            .sorted()
    }

    static func run(_ executable: String, preview: Bool) -> CommandResult {
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_COLOR"] = "1"
        return CommandRunner.run(executable, preview ? ["cleanup", "--dry-run"] : ["cleanup"],
                                 timeout: preview ? 45 : 120, environment: environment)
    }
}

struct HomebrewCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var reviewing = false
    @State private var executable: String?
    @State private var preview: String?
    @State private var outcome: String?

    var body: some View {
        DisclosureGroup("Homebrew cleanup") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview the old versions and downloads Homebrew would remove.")
                    .foregroundStyle(Theme.secondary)
                Button("Preview Homebrew cleanup…") { inspect() }.buttonStyle(QuietButton())
                    .disabled(busy || model.actionBusy)
                if busy { ProgressView().controlSize(.small) }
                if let outcome { Text(verbatim: outcome).textSelection(.enabled) }
            }.padding(.vertical, 8)
        }
        .sheet(isPresented: $reviewing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Homebrew cleanup").font(.title2)
                Text("Homebrew permanently removes the items it selects. Its cleanup does not move them to Trash.")
                ScrollView {
                    Text(verbatim: preview?.isEmpty == false ? preview ?? "" : "Homebrew returned no preview output.")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 230)
                HStack {
                    Button("Cancel") { reviewing = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Run Homebrew cleanup", role: .destructive) { execute() }
                        .disabled(HomebrewCleanup.candidates(preview ?? "").isEmpty || model.actionBusy)
                }
            }.padding(24).frame(width: 620)
        }
    }

    private func inspect() {
        busy = true
        preview = nil
        outcome = nil
        Task {
            let result = await DiskWork.run("Previewing Homebrew cleanup", lane: .interactive) {
                HomebrewCleanup.executable().map { ($0, HomebrewCleanup.run($0, preview: true)) }
            }
            busy = false
            guard let (path, result) = result else {
                outcome = "Homebrew was not found in its standard installation locations."
                return
            }
            guard result.status == 0 else { outcome = result.output; return }
            executable = path
            preview = result.output
            reviewing = true
        }
    }

    private func execute() {
        guard let executable, let preview, !model.actionBusy else { return }
        let reviewed = HomebrewCleanup.candidates(preview)
        guard !reviewed.isEmpty else { return }
        reviewing = false
        guard model.requireCleanupAccess() else { return }
        busy = true
        model.actionBusy = true
        Task {
            let result = await DiskWork.run("Running reviewed Homebrew cleanup") { () -> CommandResult? in
                let current = HomebrewCleanup.run(executable, preview: true)
                guard current.status == 0, HomebrewCleanup.candidates(current.output) == reviewed else { return nil }
                return HomebrewCleanup.run(executable, preview: false)
            }
            if let result {
                let status = result.status == 0 ? "Homebrew cleanup finished." : "Homebrew cleanup reported a failure."
                outcome = [status, result.output].filter { !$0.isEmpty }.joined(separator: "\n")
                model.refreshResources()
            } else {
                outcome = "Homebrew’s preview changed or could not be read. Preview cleanup again."
            }
            busy = false
            model.actionBusy = false
        }
    }
}
