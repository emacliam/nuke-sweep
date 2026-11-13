import SwiftUI
import AppKit

struct DockerView: View {
    @Environment(AppModel.self) var model
    @State private var review: String?
    @State private var reviewedContext = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Label(model.dockerContext.isEmpty ? "Docker context not checked" : "Context: \(model.dockerContext)", systemImage: "shippingbox").font(.system(size: 12, weight: .medium)); Spacer(); if model.dockerLoading { ProgressView().controlSize(.small) }; Button("Refresh usage") { model.inspectDocker() }.buttonStyle(QuietButton()).disabled(model.dockerLoading || model.actionBusy) }
            if let error = model.dockerError { Notice.measured(error, symbol: "exclamationmark.triangle") }
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
            if !model.dockerVolumes.isEmpty {
                SectionTitle(title: "Volumes", detail: "Read-only inventory · never pruned")
                Surface {
                    VStack(spacing: 0) {
                        HStack { Text("NAME"); Spacer(); Text("DRIVER").frame(width: 100, alignment: .trailing); Text("SCOPE").frame(width: 80, alignment: .trailing) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.bottom, 12)
                        ForEach(model.dockerVolumes) { volume in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(volume.name).fontWeight(.medium); Text(volume.mountpoint).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle) }
                                Spacer()
                                Text(volume.driver).frame(width: 100, alignment: .trailing)
                                Text(volume.scope).frame(width: 80, alignment: .trailing).foregroundStyle(Theme.secondary)
                            }.font(.system(size: 11)).padding(.vertical, 9)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Volume \(volume.name), driver \(volume.driver), scope \(volume.scope), mountpoint \(volume.mountpoint)")
                            Divider()
                        }
                    }
                }
                Notice(text: "Volumes can contain databases and user data. Nuke Sweep lists them read-only and never removes them. Manage volumes deliberately with Docker.", symbol: "internaldrive")
            } else if model.dockerReachable {
                Text("No Docker volumes returned by this context.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if let error = model.dockerVolumeError { Text(error).font(.system(size: 10)).foregroundStyle(Theme.warning) }
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
            } else if !model.dockerLoading && model.dockerError == nil {
                SuggestedStart(
                    title: "Inspect Docker storage",
                    detail: "Nuke Sweep reads disk usage through your installed Docker CLI, in the context you have selected. Volumes are inventoried read-only and never pruned.",
                    symbol: "shippingbox",
                    choices: []
                )
            }
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
struct WatchlistView: View {
    @Environment(AppModel.self) var model
    @Environment(ScheduledScanStore.self) var scheduled
    @State private var scheduleFrequency = ScanFrequency.daily
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            scheduledSection
        }
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Scheduled scans").font(.system(size: 15, weight: .semibold))
                Text("Measure on a cadence · no cleanup").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                Picker("New schedule", selection: $scheduleFrequency) {
                    ForEach(ScanFrequency.allCases) { frequency in Text(frequency.title).tag(frequency) }
                }.labelsHidden().frame(width: 110)
                Button("Add schedule…") { chooseScheduleFolder() }.buttonStyle(PrimaryButton())
            }
            HStack(spacing: 10) {
                Toggle("Quiet hours", isOn: Binding(get: { scheduled.quietHours.enabled }, set: { scheduled.setQuietHoursEnabled($0) }))
                if scheduled.quietHours.enabled {
                    DatePicker("From", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Quiet hours start")
                    DatePicker("To", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Quiet hours end")
                }
                Spacer()
                Toggle("Notify when finished", isOn: Binding(get: { scheduled.notificationsEnabled }, set: { scheduled.setNotificationsEnabled($0) }))
            }.font(.system(size: 11))
            Text("Quiet hours pause scheduled scans while Nuke Sweep is open. Manual Run now is still available. Notifications use macOS permission and contain only the folder name and result summary.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            if scheduled.scans.isEmpty {
                Surface {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 20)).foregroundStyle(Theme.orange)
                        Text("Schedule a folder measurement hourly, daily or weekly. Runs only while Nuke Sweep is open; completed scans use the normal Growth history and alert path.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            } else {
                ForEach(scheduled.scans) { scan in
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: scan.enabled ? "calendar.badge.clock" : "calendar").foregroundStyle(scan.enabled ? Theme.orange : Theme.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(scan.name).font(.system(size: 12, weight: .medium))
                                    Text(scan.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if scheduled.runningID == scan.id { ProgressView().controlSize(.mini) }
                                Picker("Frequency", selection: Binding(get: { scan.frequency }, set: { scheduled.setFrequency(scan.id, frequency: $0) })) {
                                    ForEach(ScanFrequency.allCases) { frequency in Text(frequency.title).tag(frequency) }
                                }.labelsHidden().frame(width: 100).accessibilityLabel("Scan frequency for \(scan.name)")
                                Toggle("Enabled", isOn: Binding(get: { scan.enabled }, set: { scheduled.toggle(scan.id, enabled: $0) })).labelsHidden().accessibilityLabel("Enable scheduled scan for \(scan.name)")
                                Button("Run now") { scheduled.runNow(scan.id) }.buttonStyle(QuietButton()).disabled(scheduled.runningID != nil)
                                if scheduled.runningID == scan.id { Button("Cancel") { scheduled.cancelRunning() }.buttonStyle(QuietButton()) }
                                Button("Remove") { scheduled.remove(scan.id) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                            }
                            HStack(spacing: 16) {
                                Text(scan.lastRun.map { "Last: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Never run").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                Text("Next: \(scan.nextRun.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                if let last = scan.lastResult { Text(last).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1) }
                            }
                        }
                    }
                }
            }
            if let note = scheduled.note { Text(note).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            Notice(text: "Scheduled scans run only while Nuke Sweep is open. They measure the folder and add a complete result to Growth history; they never select, move or delete files. Partial or access-limited scans are not saved as complete history.", symbol: "calendar.badge.clock")
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<ScanQuietHours, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = scheduled.quietHours[keyPath: keyPath]
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            scheduled.setQuietTime(keyPath, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        })
    }

    private func chooseScheduleFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Schedule folder"
        if panel.runModal() == .OK, let url = panel.url {
            FolderAccess.shared.remember(url)
            _ = scheduled.add(url, frequency: scheduleFrequency)
        }
    }

}
struct HistoryView: View {
    @Environment(AppModel.self) var model
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
    @Environment(AppModel.self) var model
    @Environment(AISettings.self) var ai
    @Environment(\.dismiss) var dismiss
    @State private var aiTarget: AIExplainTarget?
    @State private var blockedExpanded = true
    @State private var acknowledged = false
    @State private var openHandlesReviewed = false
    @State private var restoreReport: RestorePreflight.Report?
    var body: some View {
        let selected = model.selectedPendingTrash
        VStack(alignment: .leading, spacing: 18) {
            Label("Review file cleanup", systemImage: "trash").font(.system(size: 22, weight: .semibold))
            HStack {
                Text("\(selected.count) of \(model.pendingTrash.count) selected · \(bytes(selected.reduce(0) { $0 + $1.size })) to move to Trash")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Spacer()
                if !model.pendingTrash.isEmpty {
                    Button("Select all") { model.pendingTrashSelection = Set(model.pendingTrash.map(\.id)) }
                        .disabled(selected.count == model.pendingTrash.count)
                    Button("Clear") { model.pendingTrashSelection.removeAll() }.disabled(selected.isEmpty)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.pendingTrash) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle(item.name, isOn: Binding(
                                get: { model.pendingTrashSelection.contains(item.id) },
                                set: { include in
                                    if include { model.pendingTrashSelection.insert(item.id) }
                                    else { model.pendingTrashSelection.remove(item.id) }
                                }
                            )).toggleStyle(.checkbox).font(.system(size: 13, weight: .medium))
                            Text(item.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            if let evidence = model.pendingEvidence[item.id] {
                                let assessment = CandidateAssessment.make(item, evidence: evidence)
                                Text(assessment.state.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(assessment.state == .needsInspection ? Theme.warning : Theme.ink)
                                Text(evidence.label + " · " + evidence.detail)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(evidence.kind.isBlocked ? Theme.warning : Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let rebuild = evidence.rebuild {
                                    Text("Rebuild: " + rebuild).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if ai.enabled, let evidence = model.pendingEvidence[item.id], evidence.kind == .unknown {
                                Button("Explain with AI…") { aiTarget = AIExplainTarget(item: item, evidence: evidence, scope: nil) }
                                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
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
                Text("Only checked, verified items are included.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            if !model.pendingWarnings.isEmpty {
                Notice.measured(model.pendingWarnings.prefix(3).joined(separator: "\n") + (model.pendingWarnings.count > 3 ? "\nAnd \(model.pendingWarnings.count - 3) more open-file warnings." : ""), symbol: "exclamationmark.triangle")
            }
            let restore = restoreReport.flatMap { $0.findings.map(\.item) == selected ? $0 : nil }
            if let restore, !restore.allRestorable {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Put Back will not work for \(restore.manualOnly.count) of these", systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warning)
                    ForEach(restore.manualOnly.prefix(3)) { finding in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: finding.item.name).font(.system(size: 11, weight: .medium))
                            if let reason = finding.reason {
                                Text(verbatim: reason).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if restore.manualOnly.count > 3 {
                        Text("And \(restore.manualOnly.count - 3) more items").font(.system(size: 10))
                    }
                    Text("These still move to Trash and can be dragged back by hand. Only the one-click restore is unavailable.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.pendingTrash.isEmpty {
                Notice(text: "Checked items move to macOS Trash with their verified contents. Moving them to Trash does not immediately free disk space. The cleanup result will show restore options for eligible items.", symbol: "exclamationmark.triangle")
                Toggle("I reviewed these items and stopped tools using them.", isOn: $acknowledged).font(.system(size: 12))
                if !model.pendingWarnings.isEmpty {
                    Toggle("I closed the apps or builds listed above.", isOn: $openHandlesReviewed).font(.system(size: 12))
                }
            }
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Export plan…") { model.exportPendingPlan() }.buttonStyle(QuietButton()).disabled(selected.isEmpty)
                Spacer()
                if !selected.isEmpty && restore == nil {
                    BusyLine(text: "Checking restore options…")
                }
                Button("Move to Trash") { model.trashReviewed() }.buttonStyle(PrimaryButton()).disabled(selected.isEmpty || restore == nil || !acknowledged || (!model.pendingWarnings.isEmpty && !openHandlesReviewed) || model.actionBusy)
            }
        }.padding(30).frame(width: 580)
            .task(id: selected) {
                guard !selected.isEmpty else { restoreReport = nil; return }
                let token = ScanCancellation()
                await withTaskCancellationHandler {
                    let report = await DiskWork.run("Checking restore options", cancellation: token) {
                        RestorePreflight.inspect(selected, token: token)
                    }
                    if !Task.isCancelled { restoreReport = report }
                } onCancel: { token.cancel() }
            }
            .onChange(of: model.pendingTrashSelection) {
                acknowledged = false
                openHandlesReviewed = false
            }
            .sheet(item: $aiTarget) { (target: AIExplainTarget) in AIExplainSheet(target: target, previewBeforeSending: true) }
    }
}
/// Compact "last sweep" evidence shared by Cleanup and the menu-bar popover.
struct LastCleanupNote: View {
    @Environment(AppModel.self) var model
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

/// Takes `LocalizedStringKey` rather than `String` so a literal written at a call
/// site is a translation key, the same way SwiftUI's own `Text` behaves. Use the
/// `verbatim:` initializer for text assembled at runtime, which must not be
/// looked up as a key.
struct Notice: View {
    let text: LocalizedStringKey
    let symbol: String
    private var verbatim: String?
    init(text: LocalizedStringKey, symbol: String) { self.text = text; self.symbol = symbol; self.verbatim = nil }
    /// For notices built from measured values or provider messages. A static
    /// factory, not an overloaded init: see SectionTitle.measured.
    static func measured(_ text: String, symbol: String) -> Notice {
        var view = Notice(text: "", symbol: symbol); view.verbatim = text; return view
    }
    private var symbolColor: Color { symbol.contains("exclamationmark") ? Theme.warning : Theme.secondary }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(symbolColor)
            Group { if let verbatim { Text(verbatim: verbatim) } else { Text(text) } }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(15).frame(maxWidth: 760, alignment: .leading)
        .background(Theme.rail.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
/// Takes `LocalizedStringKey` rather than `String` so a literal written at a call
/// site is a translation key, the same way SwiftUI's own `Text` behaves. Use the
/// `verbatim:` initializer for text assembled at runtime, which must not be
/// looked up as a key.
struct EmptyPanel: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var body: some View { VStack(alignment: .leading, spacing: 16) { Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(Theme.orange); Text(title).font(.system(size: 21, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420, alignment: .leading) }.padding(.vertical, 32).frame(maxWidth: .infinity, alignment: .leading) }
}
