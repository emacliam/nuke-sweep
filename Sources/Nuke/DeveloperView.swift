import SwiftUI
import NukeMetrics

/// The Developer surface, split out of ContentView: that file had grown large
/// enough that the type checker could no longer resolve its largest bodies, and
/// these views are a self-contained concern anyway.

struct DeveloperView: View {
    @Environment(AppModel.self) var model
    @State private var expanded: String?
    @State private var selected: Set<String> = []

    /// Locations with something measured in them, largest first.
    private var rankedRules: [CacheRule] {
        CacheRule.all
            .filter { size(of: $0) > 0 }
            .sorted { size(of: $0) > size(of: $1) }
    }
    /// Measured as empty, not found, or not yet scanned.
    private var emptyRules: [CacheRule] {
        let ranked = Set(rankedRules.map(\.id))
        return CacheRule.all.filter { !ranked.contains($0.id) }
    }
    private func size(of rule: CacheRule) -> Int64 {
        model.caches.first { $0.id == rule.id }?.item?.size ?? 0
    }
    private func item(for rule: CacheRule) -> DiskItem? {
        model.caches.first { $0.id == rule.id }?.item
    }
    private var measuredTotal: Int64 { rankedRules.reduce(0) { $0 + size(of: $1) } }
    private var measuredCount: Int { rankedRules.count }
    /// The portion whose rebuild cost is a short wait rather than a long one --
    /// the part a developer can clear without planning their afternoon around it.
    private var quickReclaimTotal: Int64 {
        rankedRules.filter { RebuildCost.forCacheRule($0.id).effort <= .quick }.reduce(0) { $0 + size(of: $1) }
    }
    private var selectedRules: [CacheRule] { CacheRule.all.filter { selected.contains($0.id) } }
    private var selectedItems: [DiskItem] { selectedRules.compactMap { item(for: $0) }.filter { !$0.incomplete } }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if !model.cacheScanning {
                    HStack(spacing: 6) {
                        if model.cacheOutcome.hasPrefix("Stopped") || model.cacheOutcome.contains("partial") || model.cacheOutcome.contains("gaps") {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Theme.warning)
                        }
                        Text(model.cacheOutcome).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                }
                Spacer()
                Button(model.cacheScanning ? "Scanning…" : model.cacheOutcome == "Not scanned" ? "Scan developer caches" : "Scan again") { model.scanCaches() }.buttonStyle(PrimaryButton()).disabled(model.cacheScanning)
            }
            if measuredTotal > 0 { DeveloperTotals(bytes: measuredTotal, locations: measuredCount, reclaimable: quickReclaimTotal) }
            TriagePanel(store: model.triage)
            VStack(spacing: 0) {
                // Largest first, like every other surface. Unmeasured and
                // not-found locations sort last rather than interleaving with
                // real findings.
                ForEach(rankedRules) { rule in cacheRow(rule) }
                if !emptyRules.isEmpty {
                    DisclosureGroup(LocalizedStringKey(String(format: String(localized: "Nothing measured in %@"), Plural.otherLocations(emptyRules.count)))) {
                        ForEach(emptyRules) { rule in cacheRow(rule) }
                    }.font(.system(size: 12)).padding(.vertical, 4)
                }
            }
            if !selectedRules.isEmpty {
                DeveloperSelectionBar(
                    count: selectedRules.count,
                    bytes: selectedBytes,
                    clear: { selected.removeAll() },
                    addToBasket: { model.addToBasket(selectedItems) },
                    review: { model.reviewTrash(selectedItems) }
                )
            }
            Text("Expand a location for its path, cleanup impact and review action. Nothing is selected automatically.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Divider().padding(.vertical, 6)
            DeveloperScopesSection()
        }
    }

    /// Developer caches are exactly where "nothing has touched this in months"
    /// decides the answer, so it belongs on the row rather than behind a chevron.
    private func lastChanged(_ item: DiskItem?) -> String? {
        guard let modified = item?.lastTouched else { return nil }
        let days = max(0, Int(Date().timeIntervalSince(modified) / 86_400))
        switch days {
        case 0: return "changed today"
        case 1: return "changed yesterday"
        case ..<30: return "changed \(days) days ago"
        case ..<365: return "untouched \(days / 30) month\(days / 30 == 1 ? "" : "s")"
        default: return "untouched over a year"
        }
    }

    @ViewBuilder private func cacheRow(_ rule: CacheRule) -> some View {
        let measurement = model.caches.first { $0.id == rule.id }
        VStack(alignment: .leading, spacing: 0) {
            let cost = RebuildCost.forCacheRule(rule.id)
            // Only a complete, non-empty measurement can be selected: a partial
            // size is a lower bound, and review would be acting on a guess.
            let measured: DiskItem? = measurement?.item ?? nil
            let selectable: Bool = measured.map { !$0.incomplete && $0.size > 0 } ?? false
            HStack(spacing: 10) {
                // Multi-select, so a sweep across several caches is one review
                // rather than one review per location.
                Toggle("Select " + rule.name, isOn: Binding(
                    get: { selected.contains(rule.id) },
                    set: { on in if on { selected.insert(rule.id) } else { selected.remove(rule.id) } }
                ))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(!selectable || model.actionBusy || model.cacheScanning)
                Button { expanded = expanded == rule.id ? nil : rule.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: rule.symbol).foregroundStyle(Theme.orange).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name).fontWeight(.medium)
                            HStack(spacing: 6) {
                                if cost.effort != .unknown {
                                    Text(verbatim: cost.summary).foregroundStyle(cost.effort == .irreplaceable ? Theme.warning : Theme.secondary)
                                }
                                if let age = lastChanged(measurement?.item) {
                                    Text(verbatim: "· " + age).foregroundStyle(Theme.secondary)
                                }
                            }.font(.system(size: 10))
                        }
                        Spacer()
                        Text(measurement.map { $0.item.map { bytes($0.size) + ($0.incomplete ? "+ · partial" : "") } ?? "Not found" } ?? (model.cacheOutcome.hasPrefix("Stopped") ? "Not inspected" : "Not scanned")).monospacedDigit().foregroundStyle(Theme.secondary)
                        Image(systemName: expanded == rule.id ? "chevron.down" : "chevron.right").font(.system(size: 10)).frame(width: 12)
                    }.font(.system(size: 12)).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rule.name + ", " + (expanded == rule.id ? "hide details" : "show details") + ". " + cost.summary)
            }
            if expanded == rule.id {
                VStack(alignment: .leading, spacing: 10) {
                    Text("~/" + rule.relativePath).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Text(rule.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if let item = measurement?.item {
                        if item.incomplete { Text(model.cacheOutcome.hasPrefix("Stopped") ? "Stopped while inspecting this location. Browse smaller folders or scan again before cleanup." : (measurement?.skipped ?? 0) > 0 ? "Access incomplete. Resolve folder permissions and scan again before cleanup." : "Scan limit reached. Browse smaller folders to review cleanup.").font(.system(size: 11)).foregroundStyle(Theme.warning) }
                        if (measurement?.skipped ?? 0) > 0 { Button("Review folder access") { model.page = .permissions }.buttonStyle(QuietButton()) }
                        HStack { Button("Browse tree") { model.browseTree(item.url) }.buttonStyle(QuietButton()); Spacer(); Button("Review contents…") { model.reviewTrash([], cacheContents: rule) }.buttonStyle(QuietButton()).disabled(model.actionBusy || model.cacheScanning); Button("Review whole folder…") { model.reviewTrash([item]) }.buttonStyle(PrimaryButton()).disabled(model.actionBusy || model.cacheScanning || item.incomplete || item.size == 0) }
                    }
                }.padding(.leading, 34).padding(.bottom, 16)
            }
            Divider()
        }
    }
}


struct DeveloperTotals: View {
    let bytes: Int64
    let locations: Int
    let reclaimable: Int64
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(format: String(localized: "Measured across %@"), Plural.locations(locations)))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text(verbatim: Nuke.bytes(bytes)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            }
            if reclaimable > 0 && reclaimable != bytes {
                Rectangle().fill(Theme.line).frame(width: 1, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Comes back in seconds or minutes")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Text(verbatim: Nuke.bytes(reclaimable)).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.green)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Mirrors the Cleanup page's selection bar so a multi-location sweep ends the
/// same way every other selection in the app does -- in one review.
struct DeveloperSelectionBar: View {
    let count: Int
    let bytes: Int64
    let clear: () -> Void
    let addToBasket: () -> Void
    let review: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text("\(count) selected · \(Nuke.bytes(bytes))").font(.system(size: 12, weight: .medium))
            Button("Clear", action: clear).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.orange)
            Spacer()
            Button("Add to basket", action: addToBasket).buttonStyle(QuietButton())
            Button("Review selected…", action: review).buttonStyle(PrimaryButton())
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }
}
