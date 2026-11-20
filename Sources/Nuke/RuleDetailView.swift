import SwiftUI

/// Everything about one cleanup rule on one page: what it is, what removing it
/// costs, how it is removed, where it lives, and what is inside, largest first.
/// After Major Tom's rule pages (MIT, (c) 2026 Tom Jordan).
struct RuleDetailView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    let rule: CacheRule
    @State private var children: [DiskItem]?

    var body: some View {
        let cost = RebuildCost.forCacheRule(rule.id)
        let measurement = model.caches.first { $0.id == rule.id }?.item
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: rule.symbol).font(.system(size: 22)).foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.system(size: 20, weight: .semibold))
                    Text(measurement.map { bytes($0.size) + ($0.incomplete ? "+ · partly measured" : "") } ?? "Not measured yet")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                row("What it is", rule.detail)
                row("Comes back", cost.action ?? "Not stated")
                row("Cost", cost.effort == .unknown ? "Unknown" : cost.estimate)
                row("How it's removed", rule.reportOnly ? "It isn't. Shown for size only; clean it from inside its app."
                    : CleanupPreferences.deleteRebuildable ? "Its contents are deleted after review; the folder itself stays." : "Its contents move to Trash after review; the folder itself stays.")
                row("Where", "~/" + rule.relativePath)
            }
            Divider()
            Text("Inside, largest first").font(.system(size: 12, weight: .semibold))
            if let children {
                if children.isEmpty { Text("Empty.").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(children.prefix(40)) { child in
                            HStack {
                                Text(verbatim: child.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                                if let note = KnownCacheNotes.note(child.url) ?? (XcodeLeftovers.projectGone(child.url) ? "Its Xcode project no longer exists" : nil) {
                                    Text(verbatim: note).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(verbatim: bytes(child.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }.frame(maxHeight: 260)
            } else {
                BusyLine(text: "Measuring what's inside…")
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Show in Finder") { model.reveal(rule.url) }.buttonStyle(QuietButton())
                Spacer()
                if !rule.reportOnly, let measurement, measurement.size > 0 {
                    Button("Clear…") { dismiss(); model.reviewTrash([], cacheContents: rule) }.buttonStyle(PrimaryButton())
                }
            }
        }
        .padding(28).frame(width: 560)
        .task {
            let url = rule.url
            children = await DiskWork.run("Measuring \(rule.name)", lane: .interactive) {
                DiskScanner.scan(url, cancellation: ScanCancellation()).items
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
