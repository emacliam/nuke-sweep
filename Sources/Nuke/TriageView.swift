import SwiftUI

/// "What matters here" — the ranked shortlist with the evidence behind each rank.
///
/// Everything visible here is produced locally. The AI row is additive: it appears
/// only after an explicit request, is clearly attributed, and never changes the
/// order, the sizes or what can be selected.
struct TriagePanel: View {
    @Environment(AppModel.self) var model
    @Environment(AISettings.self) var ai
    var store: TriageStore
    @State private var showingPayload = false
    @State private var expanded = false
    /// A panel sits above the folder it describes, so it has to stay short enough
    /// not to bury it. The rest stay one click away rather than being cut.
    private let collapsedRows = 5

    var body: some View {
        if store.computing {
            Surface { BusyLine(text: "Working out what deserves attention…") }
        } else if let report = store.report, !report.isEmpty {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    header(report)
                    if let summary = store.summary { aiSummary(summary) }
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRows(report).enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { Divider().overlay(Theme.line) }
                            TriageRow(finding: finding, note: store.summary?.notes.first { $0.id == finding.id }?.note)
                        }
                    }
                    if report.findings.count > collapsedRows {
                        Button(expanded ? "Show fewer" : "Show all \(report.findings.count)") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                    }
                    footer(report)
                }
            }
            .sheet(isPresented: $showingPayload) { TriagePayloadSheet(json: store.payloadPreview) }
        }
    }

    private func visibleRows(_ report: StorageTriage.Report) -> [StorageTriage.Finding] {
        expanded ? report.findings : Array(report.findings.prefix(collapsedRows))
    }

    private func header(_ report: StorageTriage.Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(
                title: "What matters here",
                detail: "\(report.findings.count) of \(report.consideredCount) reviewed · ranked locally"
            )
            Text("Ranked by size, evidence, how long since anything changed, and whether something is using it. Nothing is selected.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func aiSummary(_ summary: AITriageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Theme.orange)
                Text(aiAttribution).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            Text(summary.headline).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            ForEach(summary.caveats, id: \.self) { caveat in
                Text("· " + caveat).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rail, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI context. " + summary.headline)
    }

    private var aiAttribution: String {
        guard case .ready(let summary, let cached) = store.aiState else { return "AI context · advisory" }
        let confidence = Int((summary.confidence * 100).rounded())
        return "AI context · \(ai.providerName(for: .explain)) · stated confidence \(confidence)%" + (cached ? " · reused" : "") + " · advisory, not a safety check"
    }

    @ViewBuilder private func footer(_ report: StorageTriage.Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !report.withheld.isEmpty { WithheldNotice(withheld: report.withheld) }
            if case .failed(let message) = store.aiState {
                Notice.measured(message, symbol: "exclamationmark.triangle")
            }
            HStack(spacing: 10) {
                if ai.enabled {
                    Button(store.isExplaining ? "Asking…" : store.summary == nil ? "Add AI context" : "Ask again") {
                        store.explain(using: ai)
                    }
                    .buttonStyle(QuietButton())
                    .disabled(store.isExplaining)
                    .help("Sends the shortlist metadata shown above to \(ai.providerName(for: .explain)). No file contents leave this Mac.")
                    Button("Show what would be sent") { showingPayload = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.orange)
                    if store.aiAddsLittle && store.summary == nil {
                        Text("Local evidence already explains this shortlist.")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Text("AI assist is off. This shortlist was produced entirely on this Mac.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                ReclaimForecast(shortlistBytes: report.shortlistBytes)
            }
        }
    }
}

private struct TriageRow: View {
    let finding: StorageTriage.Finding
    let note: String?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).foregroundStyle(Theme.secondary).frame(width: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(finding.item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            StateChip(state: finding.assessment.state)
                        }
                        Text(finding.headline).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if finding.rebuild.effort != .unknown {
                                Text(verbatim: finding.rebuild.summary)
                                    .foregroundStyle(finding.rebuild.effort == .irreplaceable ? Theme.warning : Theme.green)
                            }
                            // Only shown when the app can positively say a backup
                            // will not hold this. Unknown stays silent rather than
                            // implying either answer.
                            if finding.backup.isUnprotected {
                                Label(finding.backup.title, systemImage: "externaldrive.badge.xmark")
                                    .foregroundStyle(Theme.error)
                            }
                        }.font(.system(size: 10))
                    }
                    Spacer(minLength: 12)
                    Text(bytes(finding.item.size) + (finding.item.incomplete ? "+" : ""))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(finding.item.name), \(bytes(finding.item.size)). \(finding.headline)")
            .accessibilityHint(expanded ? "Hide the evidence" : "Show the evidence")

            if expanded { details }
        }
        .padding(.vertical, 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.orange)
                    Text(note).font(.system(size: 11)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            labelled("Evidence", finding.facts, symbol: "checkmark.circle", tint: Theme.secondary)
            labelled("Still unknown", finding.cautions, symbol: "questionmark.circle", tint: Theme.warning)
            Text(finding.assessment.reason).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 20)
    }

    @ViewBuilder private func labelled(_ title: String, _ lines: [String], symbol: String, tint: Color) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary).textCase(.uppercase)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(tint).padding(.top, 2)
                        Text(line).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct StateChip: View {
    let state: CandidateAssessment.State
    private var tint: Color {
        switch state {
        case .reviewable: return Theme.green
        case .needsInspection: return Theme.warning
        case .protected, .inspectOnly: return Theme.error
        case .checking, .measurementNeeded: return Theme.secondary
        }
    }
    var body: some View {
        Text(verbatim: state.title)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The exact bytes a provider would receive, so "what gets sent" is inspectable
/// before anything is sent rather than described in prose.
private struct TriagePayloadSheet: View {
    let json: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "What would be sent", detail: "Metadata only")
            Text("This is the complete request body. It contains no file contents, no absolute home paths, and no credentials.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(json).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 280)
            .padding(10)
            .background(Theme.rail, in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButton()) }
        }
        .padding(24)
        .frame(width: 580, height: 480)
        .background(Theme.paper)
    }
}

/// What the disk would look like afterwards.
///
/// "23.41 GB on the shortlist" is a measurement; "20.5 GB available → 44 GB" is
/// the answer to the question someone actually opened the app with. The caveat is
/// not decoration: moving to Trash does not free space until Trash is emptied,
/// and APFS snapshots and shared extents can absorb some of the rest. Showing the
/// projection without that would be the kind of promise this app refuses to make.
struct ReclaimForecast: View {
    @Environment(AppModel.self) var model
    @Environment(LiveMonitor.self) var monitor
    let shortlistBytes: Int64

    private var disk: ResourceSnapshot {
        monitor.monitorEnabled && !monitor.monitorPaused ? monitor.sample?.disk ?? model.resources : model.resources
    }

    var body: some View {
        if disk.totalDisk > 0, shortlistBytes > 0 {
            let projected = min(disk.totalDisk, disk.freeDisk + shortlistBytes)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: bytes(disk.freeDisk)).foregroundStyle(Theme.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(Theme.secondary)
                    Text(verbatim: bytes(projected)).fontWeight(.semibold).foregroundStyle(Theme.green)
                }
                .font(.system(size: 12)).monospacedDigit()
                Text("if all \(bytes(shortlistBytes)) is cleared and Trash emptied")
                    .font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Projected available storage \(bytes(projected)), up from \(bytes(disk.freeDisk)), if the whole shortlist is cleared and Trash emptied.")
        } else {
            Text(bytes(shortlistBytes) + " on the shortlist")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
        }
    }
}

/// What was kept out of the shortlist, and why.
///
/// The exposed items — nothing regenerates them, no backup holds them — are named
/// individually rather than folded into a count. A warning about the only copy of
/// someone's shipped builds is the single most valuable thing on this panel, and
/// summarising it as "3 items were held back" would waste it.
private struct WithheldNotice: View {
    let withheld: [StorageTriage.Finding]
    private var exposed: [StorageTriage.Finding] { withheld.filter { $0.withheldBecause == .irreplaceableAndUnbacked } }
    private var byAssessment: [StorageTriage.Finding] { withheld.filter { $0.withheldBecause != .irreplaceableAndUnbacked } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !exposed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No copy exists anywhere else", systemImage: "exclamationmark.shield")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.error)
                    ForEach(exposed) { finding in
                        HStack(spacing: 8) {
                            Text(verbatim: finding.item.name).font(.system(size: 11, weight: .medium))
                            Text(verbatim: bytes(finding.item.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(verbatim: finding.backup.title).font(.system(size: 10)).foregroundStyle(Theme.error)
                        }
                    }
                    Text("Nothing regenerates these and no backup holds them, so they are kept out of the shortlist. Copy anything you still need before considering removal.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if !byAssessment.isEmpty {
                Notice.measured(Plural.heldBack(byAssessment.count), symbol: "hand.raised")
            }
        }
    }
}
