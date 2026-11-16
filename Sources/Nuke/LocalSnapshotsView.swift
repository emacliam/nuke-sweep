import SwiftUI

enum LocalSnapshots {
    struct Report: Sendable {
        let timeMachine: [String]
        let otherCount: Int
        let extraCapacity: Int64?
        let listError: String?
    }

    static func parse(_ output: String) -> (timeMachine: [String], otherCount: Int) {
        let names = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let snapshots = names.filter { $0.hasPrefix("com.apple.") }
        let timeMachine = snapshots.filter { $0.hasPrefix("com.apple.TimeMachine.") }
        return (timeMachine, snapshots.count - timeMachine.count)
    }

    static func inspect() -> Report {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let extra: Int64?
        if let free = values?.volumeAvailableCapacity, let important = values?.volumeAvailableCapacityForImportantUsage,
           free >= 0, important >= 0 {
            extra = max(0, important - Int64(free))
        } else {
            extra = nil
        }
        let result = CommandRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        let list = parse(result.output)
        return Report(timeMachine: result.status == 0 ? list.timeMachine : [],
                      otherCount: result.status == 0 ? list.otherCount : 0, extraCapacity: extra,
                      listError: result.status == 0 ? nil : result.output)
    }

    static func thin() -> CommandResult {
        CommandRunner.run("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "1000000000", "1"], timeout: 90)
    }
}

struct LocalSnapshotsView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var busy = false
    @State private var confirmation = false
    @State private var report: LocalSnapshots.Report?
    @State private var outcome: String?

    var body: some View {
        DisclosureGroup("Local snapshots and purgeable space", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Time Machine keeps local restore points and macOS can remove them as space is needed.")
                if let report {
                    if let extra = report.extraCapacity {
                        Text("macOS estimates up to \(bytes(extra)) more available for important files than is currently free.")
                        Text("This estimate includes reclaimable storage across the volume. It does not measure snapshot size.")
                            .foregroundStyle(Theme.secondary)
                    } else {
                        Text("Reclaimable capacity estimate unavailable.").foregroundStyle(Theme.secondary)
                    }
                    if let error = report.listError {
                        Text("Could not list snapshots.").foregroundStyle(Theme.warning).help(error)
                    } else {
                        Text("\(report.timeMachine.count) Time Machine snapshots · \(report.otherCount) other Apple snapshots")
                        if !report.timeMachine.isEmpty {
                            DisclosureGroup("Time Machine snapshot names") {
                                ForEach(report.timeMachine, id: \.self) { Text(verbatim: $0).textSelection(.enabled) }
                            }
                            Button("Review thinning…") { confirmation = true }
                                .buttonStyle(QuietButton()).disabled(busy || model.actionBusy)
                        }
                    }
                }
                if busy { ProgressView().controlSize(.small) }
                if let outcome { Text(verbatim: outcome).textSelection(.enabled) }
                Button("Refresh snapshot report") { inspect() }.buttonStyle(QuietButton()).disabled(busy)
            }.font(.system(size: 12)).padding(.vertical, 8)
        }
        .onChange(of: expanded) { _, open in if open && report == nil && !busy { inspect() } }
        .confirmationDialog("Thin local Time Machine snapshots?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Thin snapshots", role: .destructive) { thin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Time Machine will try to reclaim 1 GB on the startup disk by permanently removing local restore points it chooses. It may reclaim less. Backups on your backup disk are separate.")
        }
    }

    private func inspect() {
        busy = true
        Task {
            report = await DiskWork.run("Inspecting local snapshots") { LocalSnapshots.inspect() }
            busy = false
        }
    }

    private func thin() {
        guard !busy, !model.actionBusy, model.requireCleanupAccess() else { return }
        model.actionBusy = true
        busy = true
        outcome = nil
        Task {
            let result = await DiskWork.run("Thinning Time Machine snapshots") { LocalSnapshots.thin() }
            outcome = result.status == 0
                ? "Time Machine finished the thinning request. Refreshing storage readings."
                : "Time Machine could not complete the request. " + result.output
            model.refreshResources()
            report = await DiskWork.run("Inspecting local snapshots") { LocalSnapshots.inspect() }
            busy = false
            model.actionBusy = false
        }
    }
}
