import SwiftUI
import AppKit

struct ApplicationsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @State private var query = ""
    @State private var chosenID: String?
    @FocusState private var filterFocused: Bool
    var filtered: [InstalledApp] { features.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Button("Inspect installed apps") { features.scanApps() }.buttonStyle(PrimaryButton()).disabled(features.appLoading); Button("Find possible leftovers") { features.findLeftovers() }.buttonStyle(QuietButton()).disabled(features.appLoading); Spacer(); Text("/Applications + ~/Applications").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            if features.appLoading { BusyLine(text: "Queued or reading app identities and related locations…") }
            if !features.appNote.isEmpty { Text(features.appNote).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            if !features.apps.isEmpty || features.leftoversScanned {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Filter apps", text: $query).textFieldStyle(.roundedBorder).focused($filterFocused)
                            .onChange(of: model.focusFilterRequest) { _, _ in filterFocused = true }
                        Table(filtered) {
                            TableColumn("Application") { app in AppChoiceRow(app: app, chosenID: $chosenID).disabled(features.appLoading) }
                        }.tableStyle(.inset(alternatesRowBackgrounds: false))
                            .frame(minHeight: 180, maxHeight: .infinity)
                            .overlay { if filtered.isEmpty { Text(query.isEmpty ? "No applications inspected." : "No apps match this filter.").font(.system(size: 11)).foregroundStyle(Theme.secondary) } }
                            .onChange(of: chosenID) { _, id in if let app = features.apps.first(where: { $0.id == id }), !features.appLoading { features.inspectApp(app) } }
                        Text("\(filtered.count) apps").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }.padding(12).frame(minWidth: 190, idealWidth: 220, maxWidth: 250).background(Theme.rail, in: RoundedRectangle(cornerRadius: 9))
                    ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let app = features.selectedApp {
                            SectionTitle(title: app.name, detail: app.version)
                            Text(app.bundleID).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            InventoryList(entries: features.appReport.entries, measured: features.appMeasured)
                            ForEach(features.appReport.notes, id: \.self) { Notice(text: $0, symbol: "info.circle") }
                        } else if features.leftoversScanned {
                            Text("Possible leftovers").font(.system(size: 16, weight: .semibold))
                            if features.leftovers.entries.isEmpty { Text("No unmatched identifier candidates found within this scan’s coverage.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                            InventoryList(entries: features.leftovers.entries, measured: features.appMeasured)
                            ForEach(features.leftovers.notes, id: \.self) { Notice(text: $0, symbol: "info.circle") }
                        } else { EmptyPanel(symbol: "app.badge", title: "Choose an application", detail: "Review the app bundle and exact identifier-based candidate files. Nothing is preselected. System applications are excluded.") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !features.appLoading { EmptyPanel(symbol: "app.badge", title: "Uninstall with context", detail: "Inspect applications to review their bundles and related files. You may need administrator permission to remove an application from /Applications; Nuke Sweep will report the failure rather than escalating.") }
        }
    }
}
/// Inspection focus is separate from the cleanup checkboxes in the details pane.
private struct AppChoiceRow: View {
    let app: InstalledApp
    @Binding var chosenID: String?
    var body: some View {
        Button { chosenID = app.id } label: {
            HStack { Text(app.name).lineLimit(1); Spacer(minLength: 4); if chosenID == app.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.orange) } }
                .font(.system(size: 12)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                .background(chosenID == app.id ? Theme.orange.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Inspect " + app.name).accessibilityAddTraits(chosenID == app.id ? .isSelected : [])
    }
}
struct StartupView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Button("Inspect startup components") { features.scanStartup() }.buttonStyle(PrimaryButton()).disabled(features.startupLoading); Spacer(); Button("Login Items settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) } }.buttonStyle(QuietButton()) }
            if features.startupLoading { BusyLine(text: "Reading startup components… an in-flight command may take a moment to finish.") }
            if !features.startupNote.isEmpty { Notice(text: features.startupNote, symbol: "info.circle") }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(features.startup) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text(item.label).font(.system(size: 13, weight: .semibold)).textSelection(.enabled); Spacer(); if item.missing { Label("Executable missing", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning) } }.font(.system(size: 10))
                        Text(item.scope + " · " + item.state).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(item.owner).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(item.executable).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).foregroundStyle(Theme.secondary)
                        HStack(spacing: 18) {
                            Button("Reveal component") { model.reveal(item.source) }.buttonStyle(.plain)
                            if item.canRemove { Button("Review plist removal…") { if let measured = InventoryService.measure(item.source) { model.reviewTrash([measured]) } }.buttonStyle(.plain).disabled(model.actionBusy) }
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                    }.padding(.vertical, 18)
                    Divider()
                }
            }
            if features.startup.isEmpty && !features.startupLoading { EmptyPanel(symbol: "power", title: "See what starts with your Mac", detail: "Inspect user and third-party launch agents/daemons and app-bundled login helpers. Enabled login-item registration remains authoritative in macOS System Settings.") }
        }
    }
}
struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @State private var keepers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(features.duplicateRoot?.path ?? "Choose a folder to compare exact contents.").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2); Spacer(); Button("Find duplicates…") { keepers = [:]; features.findDuplicates() }.buttonStyle(PrimaryButton()).disabled(features.duplicateLoading) }
            if features.duplicateLoading { BusyLine(text: "Grouping by size, streaming SHA-256, then comparing bytes…") }
            if let report = features.duplicates {
                Text("\(report.groups.count) duplicate groups · \(report.checked) entries inspected · \(report.skipped) skipped\(report.limited ? " · partial/cancelled scan" : "")").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                ForEach(report.groups) { group in
                    VStack(alignment: .leading, spacing: 13) {
                        SectionTitle(title: "\(group.files.count) identical files", detail: bytes(group.extraBytes) + " extra logical bytes")
                        Picker("Keep this copy", selection: Binding(get: { keepers[group.id] ?? group.files[0].id }, set: { keepers[group.id] = $0 })) { ForEach(group.files) { file in Text(file.url.path).tag(file.id) } }.font(.system(size: 11))
                        ForEach(group.files) { file in HStack { Text(file.url.path).lineLimit(2).truncationMode(.middle).textSelection(.enabled); Spacer(); Button("Reveal") { model.reveal(file.url) }.buttonStyle(.plain) }.font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                        HStack { Text("Contents are rechecked before cleanup.").font(.system(size: 10)).foregroundStyle(Theme.secondary); Spacer(); Button("Review other copies…") {
                            let keeperID = keepers[group.id] ?? group.files[0].id
                            guard let keeper = group.files.first(where: { $0.id == keeperID }) else { return }
                            let copies = group.files.filter { $0.id != keeperID }
                            model.reviewTrash(copies, proofs: copies.map { DuplicateProof(keeper: keeper, duplicate: $0) })
                        }.buttonStyle(QuietButton()).disabled(model.actionBusy) }
                    }.padding(.vertical, 15)
                    Divider()
                }
                if report.groups.isEmpty { Text("No exact duplicate groups found within this scan’s coverage.").font(.system(size: 13)).padding(.vertical, 20) }
            } else if !features.duplicateLoading { EmptyPanel(symbol: "square.on.square", title: "Keep a copy. Lose the repetition.", detail: "Only identical regular files are grouped. Hard-linked aliases, empty files, package contents, symbolic links, and undownloaded iCloud items are excluded. Inspection is capped at 100,000 entries.") }
            Notice(text: "Duplicate content does not imply duplicate purpose. A project or app may require its own copy. Extra logical bytes are not guaranteed recovered storage. Cleanup preserves a chosen keeper, rechecks file contents, and moves reviewed copies to Trash.", symbol: "info.circle")
        }
    }
}
struct FileUseView: View {
    @EnvironmentObject var features: FeatureModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Processes using this location").font(.system(size: 19, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(features.useURL?.path ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            if features.useLoading { BusyLine(text: "Reading visible open-file references (up to 15 seconds)…") }
            if let report = features.useReport {
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(report.uses) { use in VStack(alignment: .leading, spacing: 4) { Text("\(use.process) · PID \(use.pid)").font(.system(size: 12, weight: .semibold)); Text(use.path).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled) }; Divider() } } }.frame(maxHeight: 320)
                Notice(text: report.note, symbol: "info.circle")
            }
        }.padding(28).frame(width: 620)
    }
}
struct ReceiptsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @State private var selectedReceipt: UUID?
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    private var receipts: [CleanupReceipt] { features.receipts }
    private var filteredReceipts: [CleanupReceipt] {
        guard !query.isEmpty else { return receipts }
        return receipts.filter { receipt in
            receipt.title.localizedCaseInsensitiveContains(query) ||
            receipt.items.contains { $0.originalPath.localizedCaseInsensitiveContains(query) || $0.outcome.localizedCaseInsensitiveContains(query) }
        }
    }
    private var selected: CleanupReceipt? { filteredReceipts.first { $0.id == selectedReceipt } ?? filteredReceipts.first }
    private var movedItems: Int { receipts.reduce(0) { $0 + $1.items.filter(\.success).count } }
    private var failedItems: Int { receipts.reduce(0) { $0 + $1.items.filter { !$0.success }.count } }
    private var lastObserved: Int64? { receipts.first?.observedFreeDelta }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Cleanup receipts", detail: "Local receipts · most recent 200")
            if !receipts.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        TextField("Filter receipts", text: $query).textFieldStyle(.plain).font(.system(size: 11)).focused($filterFocused)
                    }
                    .padding(7).frame(width: 220).background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
                    .accessibilityLabel("Filter cleanup receipts")
                    Spacer()
                    Button("Export all…") { features.exportAllReceipts() }.buttonStyle(QuietButton())
                }
            }
            HStack(spacing: 28) {
                metric("Receipts", "\(receipts.count)")
                metric("Succeeded", "\(movedItems)")
                metric("Failed", "\(failedItems)", warn: failedItems > 0)
                metric("Latest observed", lastObserved.map { ($0 >= 0 ? "+" : "−") + bytes(abs($0)) } ?? "—")
                Spacer()
            }
            if features.historyLoading && receipts.isEmpty {
                BusyLine(text: "Loading saved history…")
            } else if receipts.isEmpty {
                EmptyPanel(symbol: "clock.arrow.circlepath", title: "No cleanup receipts yet", detail: "Move reviewed items to Trash and the outcome, original paths, Trash paths, and observed space change will appear here.")
            } else {
                Table(filteredReceipts, selection: $selectedReceipt) {
                    TableColumn("Date") { receipt in
                        Text(receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).monospacedDigit()
                    }.width(min: 105, ideal: 118)
                    TableColumn("Cleanup") { receipt in Text(receipt.title).font(.system(size: 11)).lineLimit(1).help(receipt.title) }.width(min: 160, ideal: 240)
                    TableColumn("Items") { receipt in Text("\(receipt.items.count)").font(.system(size: 11)).monospacedDigit() }.width(45)
                    TableColumn("Result") { receipt in
                        let failed = receipt.items.filter { !$0.success }.count
                        Text(failed == 0 ? "\(receipt.items.count) succeeded" : "\(receipt.items.count - failed) succeeded · \(failed) failed")
                            .font(.system(size: 10)).foregroundStyle(failed == 0 ? Theme.secondary : Theme.error)
                    }.width(min: 100, ideal: 115)
                    TableColumn("Observed") { receipt in
                        if let delta = receipt.observedFreeDelta {
                            Text((delta >= 0 ? "+" : "−") + bytes(abs(delta)))
                                .font(.system(size: 10)).monospacedDigit().foregroundStyle(delta > 0 ? Theme.green : Theme.secondary)
                        } else { Text("—").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }.width(85)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .frame(minHeight: 150, maxHeight: 240)
                .accessibilityLabel("Cleanup receipts")
                .overlay { if filteredReceipts.isEmpty { Text("No receipts match this filter.").font(.system(size: 11)).foregroundStyle(Theme.secondary) } }
                if let selected { receiptDetail(selected) }
            }
            Divider().padding(.vertical, 4)
            SectionTitle(title: "Earlier activity", detail: "Process quits, Docker actions, older records")
            HistoryView()
        }
        .onAppear { if selectedReceipt == nil { selectedReceipt = receipts.first?.id } }
        .onChange(of: receipts.map(\.id)) { _, ids in
            if selectedReceipt == nil || !ids.contains(selectedReceipt!) { selectedReceipt = ids.first }
        }
        .onChange(of: query) { _, _ in
            if let current = selectedReceipt, !filteredReceipts.contains(where: { $0.id == current }) {
                selectedReceipt = filteredReceipts.first?.id
            }
        }
        .onChange(of: model.focusFilterRequest) { _, _ in filterFocused = true }
    }

    private func metric(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit().foregroundStyle(warn ? Theme.error : Theme.ink)
        }
    }

    private func receiptDetail(_ receipt: CleanupReceipt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(receipt.title).font(.system(size: 13, weight: .semibold))
                Text(receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                if let delta = receipt.observedFreeDelta {
                    Text("Observed " + (delta >= 0 ? "+" : "−") + bytes(abs(delta))).font(.system(size: 10)).foregroundStyle(delta > 0 ? Theme.green : Theme.secondary)
                }
                Button("Export JSON…") { features.exportReceipt(receipt) }.buttonStyle(QuietButton())
            }
            Table(receipt.items) {
                TableColumn("Original path") { item in Text(item.originalPath).font(.system(size: 10)).lineLimit(1).truncationMode(.middle).help(item.originalPath) }
                TableColumn("Size") { item in Text(bytes(item.size)).font(.system(size: 10)).monospacedDigit() }.width(80)
                TableColumn("Outcome") { item in Text(item.outcome).font(.system(size: 10)).foregroundStyle(item.success ? Theme.secondary : Theme.error).lineLimit(2) }
                TableColumn("Trash") { item in
                    if let path = item.trashPath {
                        HStack(spacing: 6) {
                            Button("Show") { model.reveal(URL(fileURLWithPath: path)) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                            if item.success {
                                Button("Restore") { model.restoreReceiptItem(item) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary).disabled(model.actionBusy)
                            }
                        }
                    } else { Text("—").foregroundStyle(Theme.secondary) }
                }.width(110)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .frame(minHeight: 130, maxHeight: 220)
            .accessibilityLabel("Receipt item outcomes")
            Text(receipt.undo).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.rail.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
    }
}
