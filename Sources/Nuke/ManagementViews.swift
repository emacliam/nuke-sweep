import SwiftUI
import AppKit

struct ApplicationsView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
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
                            SectionTitle.measured(title: app.name, detail: app.version)
                            Text(app.bundleID).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            InventoryList(entries: features.appReport.entries, measured: features.appMeasured)
                            ForEach(features.appReport.notes, id: \.self) { Notice.measured($0, symbol: "info.circle") }
                        } else if features.leftoversScanned {
                            Text("Possible leftovers").font(.system(size: 16, weight: .semibold))
                            if features.leftovers.entries.isEmpty { Text("No unmatched identifier candidates found within this scan’s coverage.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                            InventoryList(entries: features.leftovers.entries, measured: features.appMeasured)
                            ForEach(features.leftovers.notes, id: \.self) { Notice.measured($0, symbol: "info.circle") }
                        } else { EmptyPanel(symbol: "app.badge", title: "Choose an application", detail: "Review the app bundle and exact identifier-based candidate files. Nothing is preselected. System applications are excluded.") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if !features.appLoading {
                SuggestedStart(
                    title: "Uninstall with context",
                    detail: "Review an app's bundle and the files that may belong to it. Nothing is preselected and system applications are excluded. Removing from /Applications may need administrator permission; Nuke Sweep reports the failure rather than escalating.",
                    symbol: "app.badge",
                    choices: []
                )
            }
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
struct FileUseView: View {
    @Environment(FeatureModel.self) var features
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Processes using this location").font(.system(size: 19, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(features.useURL?.path ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            if features.useLoading { BusyLine(text: "Reading visible open-file references (up to 15 seconds)…") }
            if let report = features.useReport {
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(report.uses) { use in VStack(alignment: .leading, spacing: 4) { Text("\(use.process) · PID \(use.pid)").font(.system(size: 12, weight: .semibold)); Text(use.path).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled) }; Divider() } } }.frame(maxHeight: 320)
                Notice.measured(report.note, symbol: "info.circle")
            }
        }.padding(28).frame(width: 620)
    }
}
struct ReceiptsView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
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

    /// Sum of the space actually observed to come back, across every kept receipt.
    ///
    /// Only gains count: a receipt whose observed delta is negative means other
    /// activity consumed space during the cleanup, which is not a loss this app
    /// caused and must not be subtracted from the user's total. Receipts are
    /// capped at the most recent 200, so this is "to date" within what is kept,
    /// which is what the label says.
    private var lifetimeReclaimed: String {
        let gained = receipts.compactMap(\.observedFreeDelta).filter { $0 > 0 }.reduce(0, +)
        return gained > 0 ? bytes(gained) : "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Cleanup receipts", detail: "Local receipts · most recent 200")
            if !receipts.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        TextField("Filter receipts", text: $query).textFieldStyle(.plain).font(.system(size: 11)).focused($filterFocused)
                    }
                    .padding(7).frame(width: 220).background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
                    .accessibilityLabel("Filter cleanup receipts")
                    Spacer()
                    Button("Export all…") { features.exportAllReceipts() }.buttonStyle(QuietButton())
                }
            }
            if !receipts.isEmpty {
                HStack(spacing: 28) {
                    metric("Receipts", "\(receipts.count)")
                    metric("Succeeded", "\(movedItems)")
                    metric("Failed", "\(failedItems)", warn: failedItems > 0)
                    metric("Latest observed", lastObserved.map { ($0 >= 0 ? "+" : "−") + bytes(abs($0)) } ?? "—")
                    metric("Recovered to date", lifetimeReclaimed)
                    Spacer()
                }
            }
            if features.historyLoading && receipts.isEmpty {
                BusyLine(text: "Loading saved history…")
            } else if receipts.isEmpty {
                // Receipts and activities are separate stores, so an older record
                // can exist with no receipt behind it. Saying "nothing has
                // happened" while the table below lists a cleanup is a plain
                // contradiction; say what is actually missing instead.
                EmptyPanel(
                    symbol: "clock.arrow.circlepath",
                    title: model.activities.isEmpty ? "No cleanup receipts yet" : "No detailed receipts kept",
                    detail: model.activities.isEmpty
                        ? "Move reviewed items to Trash and the outcome, original paths, Trash paths, and observed space change will appear here."
                        : "Earlier activity is recorded below, but no itemised receipt was kept for it — receipts begin at the first cleanup this version performs. New cleanups record original paths, Trash paths and observed space change."
                )
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
            if selectedReceipt.map({ !ids.contains($0) }) ?? true { selectedReceipt = ids.first }
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
                    if item.restoredAt != nil {
                        Text("Restored").foregroundStyle(Theme.secondary)
                    } else if let path = item.trashPath {
                        HStack(spacing: 6) {
                            Button("Show") { model.reveal(URL(fileURLWithPath: path)) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                            if item.success && item.restoreEvidence != nil {
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
