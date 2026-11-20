import AppKit
import SwiftUI

extension AppModel {
    /// Asks for a folder on another drive, then offloads each item there.
    func offload(_ urls: [URL]) {
        guard !urls.isEmpty, !actionBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Offload here"
        panel.message = "Choose a folder on an external or network drive. Each item is copied, checked, and only then moved to Trash."
        if let last = UserDefaults.standard.string(forKey: "nuke.offloadDestination") { panel.directoryURL = URL(fileURLWithPath: last) }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        UserDefaults.standard.set(destination.path, forKey: "nuke.offloadDestination")
        actionBusy = true
        Task {
            let token = ScanCancellation()
            let outcomes = await DiskWork.run("Offloading to \(destination.lastPathComponent)", lane: .interactive, cancellation: token) { () -> [String] in
                urls.map { url in
                    do {
                        let record = try OffloadEngine.offload(url, to: destination, token: token)
                        return "Offloaded \(url.lastPathComponent): \(bytes(record.bytes)), \(record.files) files verified."
                    } catch { return "\(url.lastPathComponent) stayed where it is. \(error.localizedDescription)" }
                }
            }
            actionBusy = false
            record("Offload", detail: outcomes.joined(separator: "\n"))
            message = outcomes.joined(separator: "\n")
            personalFilesMoved(urls.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) })
            refreshResources()
        }
    }

    func restoreOffload(_ record: OffloadRecord) {
        guard !actionBusy else { return }
        actionBusy = true
        Task {
            let outcome = await DiskWork.run("Restoring \(URL(fileURLWithPath: record.originalPath).lastPathComponent)", lane: .interactive) { () -> String in
                do { return "Restored and verified at " + (try OffloadEngine.restore(record)).path }
                catch { return "Not restored. " + error.localizedDescription }
            }
            actionBusy = false
            message = outcome
            self.record("Offload restore", detail: outcome)
        }
    }
}

/// Everything offloaded, with where the copy lives and a verified restore.
struct OffloadedList: View {
    @Environment(AppModel.self) var model
    @State private var records = OffloadLog.all()
    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Offloaded", detail: "Copied to another drive, checked, then moved to Trash")
                ForEach(records) { record in
                    let available = FileManager.default.fileExists(atPath: record.copyPath)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: URL(fileURLWithPath: record.originalPath).lastPathComponent).font(.system(size: 12, weight: .medium))
                            Text(verbatim: "\(bytes(record.bytes)) · \(record.date.formatted(date: .abbreviated, time: .omitted)) · " + (available ? record.copyPath : "drive not connected"))
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if record.restored != nil { Text("Restored").font(.system(size: 10)).foregroundStyle(Theme.green) }
                        Button { model.reveal(URL(fileURLWithPath: record.copyPath)) } label: { Image(systemName: "folder") }
                            .buttonStyle(HoverPlain()).foregroundStyle(Theme.secondary).disabled(!available).help("Show the copy in Finder")
                        Button("Restore") { model.restoreOffload(record); records = OffloadLog.all() }
                            .buttonStyle(QuietButton()).disabled(!available || model.actionBusy)
                    }
                    Divider()
                }
            }
            .onAppear { records = OffloadLog.all() }
        }
    }
}
