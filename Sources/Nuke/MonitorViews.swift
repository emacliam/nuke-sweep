import SwiftUI
import AppKit

struct DockerView: View {
    @EnvironmentObject var model: AppModel
    @State private var review: String?
    @State private var reviewedContext = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Label(model.dockerContext.isEmpty ? "Docker context not checked" : "Context: \(model.dockerContext)", systemImage: "shippingbox").font(.system(size: 12, weight: .medium)); Spacer(); if model.dockerLoading { ProgressView().controlSize(.small) }; Button("Refresh usage") { model.inspectDocker() }.buttonStyle(QuietButton()).disabled(model.dockerLoading || model.actionBusy) }
            if let error = model.dockerError { Notice(text: error, symbol: "exclamationmark.triangle") }
            HStack {
                Text(model.dockerLoading ? "Checking engine…" : model.dockerReachable ? "Engine reachable" : "Engine not verified / unavailable").font(.system(size: 12, weight: .medium))
                Spacer()
                Button(model.dockerReachable ? "Open Docker Desktop" : "Start Docker and refresh") { if model.dockerReachable { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app")) } else { model.startDockerAndRefresh() } }.buttonStyle(QuietButton()).disabled(model.dockerLoading)
                if model.dockerStarting { Button("Stop waiting") { model.cancelDockerWait() }.buttonStyle(QuietButton()) }
            }
            if let updated = model.dockerUpdated { Text((model.dockerReachable ? "Measured " : "Last successful measurement — stale: ") + updated.formatted()).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            if !model.dockerDisks.isEmpty {
                SectionTitle(title: "Local Docker disk", detail: "Read-only file metadata · independent of engine")
                ForEach(model.dockerDisks) { disk in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(disk.name).fontWeight(.medium); Spacer(); Text(bytes(disk.allocated) + " allocated").monospacedDigit(); Button("Reveal") { model.reveal(disk.url) }.buttonStyle(QuietButton()) }
                        Text(bytes(disk.size) + " logical capacity · not reclaimable space").foregroundStyle(Theme.secondary)
                    }.font(.system(size: 11))
                }
                Text("This VM disk contains Docker data. Nuke Sweep never removes it directly. Default locations only; custom paths may be missing. Local disk size is unrelated to a remote context’s usage.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else { Text("No local VM disk metadata available at the default locations. It may be elsewhere or inaccessible. This does not mean Docker uses zero space.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            if !model.docker.isEmpty {
                Surface {
                    VStack(spacing: 0) {
                        HStack { Text("TYPE"); Spacer(); Text("COUNT").frame(width: 60, alignment: .trailing); Text("SIZE").frame(width: 100, alignment: .trailing); Text("RECLAIMABLE").frame(width: 160, alignment: .trailing) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.bottom, 16)
                        ForEach(model.docker) { row in
                            HStack { Text(row.type).fontWeight(.medium); Spacer(); Text(row.total).frame(width: 60, alignment: .trailing); Text(row.size).frame(width: 100, alignment: .trailing); Text(row.reclaimable).frame(width: 160, alignment: .trailing).foregroundStyle(Theme.secondary) }.font(.system(size: 12)).padding(.vertical, 15)
                            Divider()
                        }
                    }
                }
                Text("Choose a cleanup").font(.system(size: 15, weight: .semibold))
                ForEach(["Build cache", "Dangling images", "Stopped containers"], id: \.self) { kind in
                    HStack { VStack(alignment: .leading, spacing: 6) { Text(kind).font(.system(size: 13, weight: .semibold)); Text(explanation(kind)).font(.system(size: 11)).foregroundStyle(Theme.secondary) }; Spacer(); Button("Review…") { reviewedContext = model.dockerContext; review = kind }.buttonStyle(QuietButton()).disabled(model.actionBusy || model.dockerLoading || !model.dockerReachable) }
                    Divider()
                }
                Notice(text: "Usage is a snapshot. Docker decides which objects are eligible when cleanup runs. Volumes are excluded from these actions. Docker cleanup cannot be undone in Trash.", symbol: "info.circle")
            } else if !model.dockerLoading && model.dockerError == nil { EmptyPanel(symbol: "shippingbox", title: "Inspect Docker storage", detail: "Nuke Sweep uses your installed Docker CLI to read disk usage in the selected context.") }
        }
        .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Review Docker cleanup", systemImage: "shippingbox").font(.title2.weight(.semibold))
                Text(review ?? "").font(.headline)
                Text("Context: \(reviewedContext)").font(.system(size: 12, design: .monospaced))
                Text(explanation(review ?? "")).font(.system(size: 13))
                Notice(text: "This permanently removes eligible Docker objects. The command may include objects created after the last usage refresh. Stopped containers can contain data in their writable layers.", symbol: "exclamationmark.triangle")
                HStack { Button("Cancel") { review = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Run cleanup") { let kind = review ?? ""; review = nil; model.pruneDocker(kind, reviewedContext: reviewedContext) }.buttonStyle(PrimaryButton()).disabled(!model.dockerReachable || model.dockerLoading) }
            }.padding(30).frame(width: 520)
        }
    }
    func explanation(_ kind: String) -> String {
        switch kind { case "Build cache": return "Remove unused builder cache. Future builds may take longer."; case "Dangling images": return "Remove dangling images unused by containers. Named images are not selected by this action."; default: return "Remove all stopped containers, including their writable layers." }
    }
}
struct ProcessesView: View {
    @EnvironmentObject var model: AppModel
    @State private var review: ProcessRow?
    @State private var sortMemory = false
    var rows: [ProcessRow] { sortMemory ? model.visibleProcesses.sorted { $0.memory > $1.memory } : model.visibleProcesses }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let error = model.processError { Notice(text: error, symbol: "exclamationmark.triangle") }
            HStack(spacing: 25) {
                VStack(alignment: .leading, spacing: 5) { Text("1-minute load").font(.system(size: 10)).foregroundStyle(Theme.secondary); Text(String(format: "%.2f", model.resources.load)).font(.system(size: 21, weight: .medium)).monospacedDigit() }
                VStack(alignment: .leading, spacing: 5) { Text("Active CPU cores").font(.system(size: 10)).foregroundStyle(Theme.secondary); Text("\(model.resources.processors)").font(.system(size: 21, weight: .medium)) }
                VStack(alignment: .leading, spacing: 5) { Text("Physical memory").font(.system(size: 10)).foregroundStyle(Theme.secondary); Text(bytes(model.resources.physicalMemory)).font(.system(size: 21, weight: .medium)) }
                Spacer(); Button("Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }.buttonStyle(QuietButton()); Button("Refresh processes") { model.refreshProcesses() }.buttonStyle(QuietButton()).disabled(model.processLoading)
            }
            HStack { Text("\(model.processes.count) processes · snapshot on refresh").font(.system(size: 11)).foregroundStyle(Theme.secondary); Spacer(); Picker("Sort by", selection: $sortMemory) { Text("CPU").tag(false); Text("Memory").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 150) }
            LazyVStack(spacing: 0) {
                HStack { Text("PROCESS"); Spacer(); Text("CPU").frame(width: 70, alignment: .trailing); Text("MEMORY").frame(width: 95, alignment: .trailing); Text("ACTION").frame(width: 65, alignment: .trailing) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary).padding(14).background(Theme.rail)
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Image(systemName: "app.dashed").foregroundStyle(Theme.secondary).frame(width: 23)
                        VStack(alignment: .leading, spacing: 3) { Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1); Text("PID \(row.pid)").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                        Spacer(); Text(String(format: "%.1f%%", row.cpu)).frame(width: 70, alignment: .trailing); Text(bytes(row.memory)).frame(width: 95, alignment: .trailing)
                        Button("Quit…") { review = row }.buttonStyle(.borderless).disabled(row.owner != getuid() || row.pid == getpid() || row.pid <= 1).frame(width: 65, alignment: .trailing)
                    }.font(.system(size: 11)).monospacedDigit().padding(.horizontal, 14).padding(.vertical, 11)
                    Divider()
                }
                if rows.isEmpty { Text(model.processLoading ? "Reading processes…" : "No matching processes.").font(.system(size: 12)).padding(30) }
            }.background(.white).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
            Text("CPU uses ps sampling semantics and may exceed 100% across cores. Memory is resident size, not unique memory; shared pages may be counted by multiple processes.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
        .alert("Quit \(review?.name ?? "process")?", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
            Button("Cancel", role: .cancel) { review = nil }
            Button("Request quit", role: .destructive) { if let row = review { model.terminate(row) }; review = nil }
        } message: { Text("Unsaved work may be lost. Nuke Sweep requests a normal app quit, or sends SIGTERM to a background process. The process identity is checked again first.") }
    }
}
struct WatchlistView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Folder watch").font(.system(size: 15, weight: .semibold)); Spacer(); Button("Choose folder…") { model.chooseFolder(forWatch: true) }.buttonStyle(PrimaryButton()) }
            if let url = model.watchURL {
                Surface {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 12) { Image(systemName: "folder.fill").font(.system(size: 27)).foregroundStyle(Theme.orange); VStack(alignment: .leading, spacing: 5) { Text(url.lastPathComponent).font(.system(size: 16, weight: .semibold)); Text(url.path).font(.system(size: 11)).foregroundStyle(Theme.secondary).textSelection(.enabled) }; Spacer(); Text(model.watching ? "Watching" : "Paused").font(.system(size: 11, weight: .medium)).foregroundStyle(model.watching ? Theme.green : Theme.secondary) }
                        Divider()
                        HStack(alignment: .top, spacing: 50) {
                            metric("Current size", value: model.watchSize.map(bytes) ?? "Measuring…")
                            metric("Change since start", value: growth)
                            metric("Folder events", value: "\(model.watchEvents)")
                        }
                        HStack(spacing: 8) {
                            Button("Show in Finder") { model.reveal(url) }.buttonStyle(QuietButton())
                            Button("Change folder…") { model.chooseFolder(forWatch: true) }.buttonStyle(QuietButton())
                            Spacer()
                            if model.watchScanning { ProgressView().controlSize(.small) }
                            Button(model.watching ? "Pause watch" : "Resume watch") { if model.watching { model.stopWatching() } else { model.startWatching(url) } }.buttonStyle(QuietButton())
                            Button("Remove watch") { model.removeWatch() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                if let error = model.watchError { Notice(text: error, symbol: "exclamationmark.triangle") }
                Notice(text: "Watches immediate folder changes and reconciles nested size every 30 seconds while Nuke Sweep is open. Event counts are notifications, not individual file edits. Watching pauses when you quit; Remove watch stops tracking and forgets the folder without touching files.", symbol: "info.circle")
            } else { EmptyPanel(symbol: "eye", title: "Give a folder your attention", detail: "Watch Downloads, a build directory, or a cache. Nuke Sweep tracks its size and change from the moment you start.") }
        }
    }
    var growth: String { guard let baseline = model.watchBaseline, let size = model.watchSize else { return "—" }; let delta = size - baseline; return (delta > 0 ? "+" : delta < 0 ? "−" : "") + bytes(abs(delta)) }
    func metric(_ label: String, value: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary); Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit() } }
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.activities.isEmpty {
            Text("Process quit requests, Docker actions, and older records will appear here.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        } else {
            Table(model.activities) {
                TableColumn("Date") { activity in Text(activity.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).monospacedDigit() }.width(min: 115, ideal: 130)
                TableColumn("Action") { activity in Text(activity.title).font(.system(size: 11)).lineLimit(1) }.width(min: 110, ideal: 140)
                TableColumn("Detail") { activity in Text(activity.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2) }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .frame(minHeight: 120, maxHeight: 180)
            .accessibilityLabel("Earlier Nuke Sweep activity")
        }
    }
}
struct TrashReview: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var blockedExpanded = true
    @State private var acknowledged = false
    @State private var openHandlesReviewed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Review file cleanup", systemImage: "trash").font(.system(size: 22, weight: .semibold))
            Text("\(model.pendingTrash.count) \(model.pendingTrash.count == 1 ? "item" : "items") · \(bytes(model.pendingTrash.reduce(0) { $0 + $1.size })) logical size").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.pendingTrash) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).font(.system(size: 13, weight: .medium))
                            Text(item.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            if let evidence = model.pendingEvidence[item.id] {
                                Text(evidence.label + " · " + evidence.detail)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(evidence.kind.isBlocked ? Theme.warning : Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let rebuild = evidence.rebuild {
                                    Text("Rebuild: " + rebuild).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }.frame(maxHeight: 220)
            if !model.pendingBlocked.isEmpty {
                DisclosureGroup("Not included · \(model.pendingBlocked.count) could not be verified", isExpanded: $blockedExpanded) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.pendingBlocked) { blocked in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(blocked.url.lastPathComponent).font(.system(size: 12, weight: .medium))
                                    Text(blocked.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    HStack {
                                        Button("Show in Finder") { model.reveal(blocked.url) }
                                        Button("Browse smaller folders") { dismiss(); model.browseTree(blocked.url) }
                                    }.font(.system(size: 11))
                                }
                            }
                        }
                    }.frame(maxHeight: 150)
                }.font(.system(size: 12)).foregroundStyle(Theme.warning)
                Text("Only the verified items listed above are included. Nothing has been moved.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if !model.pendingWarnings.isEmpty {
                Notice(text: model.pendingWarnings.prefix(3).joined(separator: "\n") + (model.pendingWarnings.count > 3 ? "\nAnd \(model.pendingWarnings.count - 3) more open-file warnings." : ""), symbol: "exclamationmark.triangle")
            }
            if !model.pendingTrash.isEmpty {
                Notice(text: "These items will move to macOS Trash. Space is reclaimed only after Trash is emptied. Folders move with everything inside, including files added since the scan; Nuke Sweep blocks project roots, source-control metadata, credentials, and personal data stores. Stop apps or builds using these files and review folders in Finder first.", symbol: "exclamationmark.triangle")
                Toggle("I reviewed these items and stopped tools using them.", isOn: $acknowledged).font(.system(size: 12))
                if !model.pendingWarnings.isEmpty {
                    Toggle("I closed the apps or builds listed above.", isOn: $openHandlesReviewed).font(.system(size: 12))
                }
            }
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export plan…") { model.exportPendingPlan() }.buttonStyle(QuietButton()).disabled(model.pendingTrash.isEmpty)
                Spacer()
                Button("Move to Trash") { model.trashReviewed() }.buttonStyle(PrimaryButton()).disabled(model.pendingTrash.isEmpty || !acknowledged || (!model.pendingWarnings.isEmpty && !openHandlesReviewed) || model.actionBusy)
            }
        }.padding(30).frame(width: 580)
    }
}
/// Compact "last sweep" evidence shared by Cleanup and the menu-bar popover.
struct LastCleanupNote: View {
    @EnvironmentObject var model: AppModel
    let receipt: CleanupReceipt
    var compact = false
    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                Text("Last sweep \(receipt.date.formatted(.relative(presentation: .named))) · \(receipt.items.count) \(receipt.items.count == 1 ? "item" : "items")")
                    .font(.system(size: 9)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer()
            }
        } else {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text("Last cleanup " + receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text("· \(receipt.items.count) \(receipt.items.count == 1 ? "item" : "items")").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if let delta = receipt.observedFreeDelta {
                    Text((delta >= 0 ? "+" : "−") + bytes(abs(delta)) + " free observed")
                        .font(.system(size: 10)).foregroundStyle(delta > 0 ? Theme.green : Theme.secondary)
                        .help("Observed volume change after cleanup; other activity can affect it.")
                }
                Spacer()
                Button("History") { model.page = .history }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
            }
        }
    }
}

struct Notice: View {
    let text: String
    let symbol: String
    private var symbolColor: Color { symbol.contains("exclamationmark") ? Theme.warning : Theme.secondary }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(symbolColor)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(15).frame(maxWidth: 760, alignment: .leading)
        .background(Theme.rail.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View { VStack(alignment: .leading, spacing: 16) { Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(Theme.orange); Text(title).font(.system(size: 21, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420, alignment: .leading) }.padding(.vertical, 32).frame(maxWidth: .infinity, alignment: .leading) }
}
