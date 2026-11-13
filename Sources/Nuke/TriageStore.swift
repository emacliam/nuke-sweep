import Foundation

/// Owns the "what matters here" panel.
///
/// Kept out of `AppModel` on purpose: triage is a self-contained concern, and a
/// separate observable means ranking progress and AI state invalidate only the
/// panel rather than every view observing the app model.
///
/// The local ranking is the feature. It runs on a scan result with no network and
/// no provider configured, and is what the panel shows. `explain` is an explicit,
/// cached, opt-in enhancement that never changes the ranking.
@Observable @MainActor final class TriageStore {
    enum AIState: Equatable {
        case idle
        case running
        case ready(AITriageSummary, fromCache: Bool)
        case failed(String)
    }

    private(set) var report: StorageTriage.Report?
    private(set) var computing = false
    private(set) var aiState: AIState = .idle
    private(set) var rootName = ""
    /// Rebuilt whenever the ranked set changes, so a stale answer is never shown
    /// against a new shortlist.
    private var context: AITriageContext?
    private var generation = UUID()

    var summary: AITriageSummary? {
        if case .ready(let value, _) = aiState { return value }
        return nil
    }
    var isExplaining: Bool { aiState == .running }

    /// Ranks a measured set. Classification touches the filesystem, so the work
    /// goes to the interactive disk lane rather than blocking the main actor.
    func refresh(items: [DiskItem], rootName: String, signals: StorageTriage.Signals = StorageTriage.Signals()) {
        guard !items.isEmpty else { clear(); return }
        let id = UUID(); generation = id
        self.rootName = rootName
        computing = true
        // A new ranked set is a new question; drop any answer about the old one.
        aiState = .idle
        Task {
            let ranked = await DiskWork.run("Reviewing what matters", lane: .interactive) {
                // Two passes on purpose. `tmutil isexcluded` is a process spawn,
                // so asking it about every measured item would cost seconds; the
                // shortlist is bounded. Coverage can only ever lower a score, so
                // an item that missed the first cut cannot be promoted by it --
                // re-ranking the shortlist alone is complete, not an approximation.
                let first = StorageTriage.rank(items, signals: signals)
                guard !first.findings.isEmpty else { return first }
                var enriched = signals
                // The shortlist, plus anything irreplaceable wherever it ranked:
                // those are the only items coverage can withhold, and missing one
                // because it sat below the cut would hide the warning that matters.
                var asked = Set<String>()
                for item in first.findings.map(\.item) + first.irreplaceable where asked.insert(item.id).inserted {
                    enriched.backupCoverage[item.id] = BackupCoverageService.coverage(for: item.url)
                }
                // The second pass sees the same full set, not just the shortlist:
                // re-ranking a subset would report a `consideredCount` covering
                // only what survived the first cut. Items with no coverage entry
                // resolve to `.unknown`, which leaves their score untouched.
                return StorageTriage.rank(items, signals: enriched)
            }
            guard generation == id else { return }
            report = ranked
            context = AITriageContext(report: ranked, rootName: rootName)
            computing = false
        }
    }

    func clear() {
        generation = UUID()
        report = nil; context = nil; computing = false; aiState = .idle; rootName = ""
    }

    /// True when local evidence already explains every item on the shortlist, so
    /// a provider has little to add. Surfaced to the user rather than acted on:
    /// asking anyway stays their call.
    var aiAddsLittle: Bool {
        guard let report, !report.findings.isEmpty else { return true }
        return !report.findings.contains { $0.driver == .unverified } && report.findings.count <= 3
    }

    /// One bounded request for the whole shortlist, answered from cache when the
    /// same shortlist has already been asked of the same provider under the same
    /// policy. Never called automatically.
    func explain(using ai: AISettings) {
        guard let context, !isExplaining else { return }
        guard ai.enabled else { aiState = .failed(AIProviderError.disabled.localizedDescription); return }
        let provider = ai.provider(for: .explain)
        let policy = ai.offlineOnly ? "offline-only" : "cloud-allowed"
        let key = context.fingerprint(provider: provider.id.uuidString, model: provider.model, policy: policy)

        if let cached = AIResponseCache.shared.value(for: key) {
            Log.ai.info("Triage answered from cache: provider=\(provider.name, privacy: .public) rows=\(context.rows.count, privacy: .public)")
            aiState = .ready(cached, fromCache: true)
            ai.record(provider: provider.name, item: "Triage · \(context.rows.count) items", outcome: "cached", milliseconds: 0)
            return
        }

        let id = generation
        aiState = .running
        Task {
            let began = Date()
            do {
                let client = try await ai.makeProvider(for: .explain)
                let summary = try await client.triage(context)
                guard generation == id else { return }
                Log.ai.info("Triage request succeeded: provider=\(provider.name, privacy: .public) rows=\(context.rows.count, privacy: .public) notes=\(summary.notes.count, privacy: .public) ms=\(Int(Date().timeIntervalSince(began) * 1000), privacy: .public)")
                AIResponseCache.shared.store(summary, for: key)
                aiState = .ready(summary, fromCache: false)
                ai.record(provider: provider.name, item: "Triage · \(context.rows.count) items", outcome: "success", milliseconds: Int(Date().timeIntervalSince(began) * 1000))
            } catch {
                guard generation == id else { return }
                // The message can quote provider output, so it stays private.
                Log.ai.error("Triage request failed: provider=\(provider.name, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                aiState = .failed(error.localizedDescription)
                ai.record(provider: provider.name, item: "Triage · \(context.rows.count) items", outcome: "failed", milliseconds: Int(Date().timeIntervalSince(began) * 1000))
            }
        }
    }

    /// The exact metadata a provider would receive, for the payload preview.
    var payloadPreview: String { context?.jsonString ?? "{}" }
}
