import Foundation

/// A local, deterministic answer to "of everything measured here, what actually
/// deserves my attention, and why these over the others?"
///
/// This runs with no network and no AI provider. Ranking, selectability and every
/// stated fact come from local evidence only. The AI layer in `AITriage` narrates
/// the shortlist this produces; it can never reorder it, add to it, or promote an
/// item's assessment state — the same invariant the review planner already holds.
enum StorageTriage {
    /// Extra local context the caller may have gathered. All of it is optional:
    /// triage degrades to size-and-evidence ranking when nothing is supplied.
    struct Signals: Sendable {
        /// Project roots with a running development process or listening port.
        /// Anything beneath one is in use and must not be promoted.
        var activeRoots: Set<String> = []
        /// Item id to bytes recoverable by dropping confirmed extra copies.
        var duplicateExtraBytes: [String: Int64] = [:]
        /// Paths sitting inside a repository with uncommitted work. The build
        /// output itself may be disposable, but it sits beside work that is not.
        var uncommittedRoots: Set<String> = []
        /// Paths a running process currently holds open. The app already learns
        /// this at review time; knowing it while ranking stops something in use
        /// from leading the shortlist in the first place.
        var openPaths: Set<String> = []
        /// Backup coverage per item id. Absent means the question was not asked.
        var backupCoverage: [String: BackupCoverage] = [:]
        /// Project roots whose repository state was never checked, because they
        /// were found outside the chosen code folder. Their build folders rank
        /// like any other, but an unattended cleanup leaves them for a person:
        /// nobody has confirmed there is no unsaved work beside them.
        var manualOnlyRoots: Set<String> = []
        var now = Date()
        init() {}
    }

    /// Why an item earned its rank. The dominant factor becomes the headline, so
    /// the ordering is always explainable without consulting a model.
    enum Driver: String, Sendable {
        case staleCache = "stale_cache"
        case largeRebuildable = "large_rebuildable"
        case duplicateCopies = "duplicate_copies"
        case recentlyUsed = "recently_used"
        case inUse = "in_use"
        case unverified = "unverified"
    }

    /// Why an item was kept out of the actionable shortlist.
    enum Withholding: String, Sendable {
        /// The local assessment refused it: protected, source-like, or unmeasured.
        case assessment
        /// Nothing regenerates it and no backup holds it. Suppressing such an item
        /// by score would bury a 2 GB warning beneath a 2 MB cache; it is held out
        /// and explained instead, which is the only way the warning gets read.
        case irreplaceableAndUnbacked
    }

    struct Finding: Identifiable, Sendable {
        let item: DiskItem
        let assessment: CandidateAssessment
        let evidence: CleanupEvidence?
        let score: Double
        let driver: Driver
        let rebuild: RebuildCost
        let backup: BackupCoverage
        var withheldBecause: Withholding?
        /// True when something about this item calls for a person's judgement:
        /// it is in use, sits beside unsaved work, was only partly measured, or
        /// has no positive evidence. Missing backup coverage is deliberately not
        /// one of these: for something that rebuilds itself, a backup is beside
        /// the point, and counting it would rule out every item on a Mac with no
        /// Time Machine.
        var needsPerson = false
        let headline: String
        let facts: [String]
        let cautions: [String]
        var id: String { assessment.id }
        var reclaimableBytes: Int64 { item.size }
    }

    struct Report: Sendable {
        let findings: [Finding]
        /// Candidates the local policy withheld, so the shortlist stays actionable
        /// without hiding that something was set aside.
        let withheld: [Finding]
        let consideredCount: Int
        let shortlistBytes: Int64
        /// Totals over every ranked candidate, not only the visible shortlist, so
        /// a headline figure describes the whole scan rather than its top rows.
        var totals = Totals()
        /// Ranked items nothing regenerates. Few by nature; exposed so the caller
        /// can ask about their backup coverage even when they miss the shortlist.
        var irreplaceable: [DiskItem] = []
        /// Candidates that come back by themselves and that nothing is using,
        /// largest first and bounded, for a caller that wants to take the whole
        /// regenerable set to review in one step.
        var regenerable: [DiskItem] = []
        /// The stricter subset an unattended cleanup may consider: positively
        /// identified as a cache, dependency folder or build output, and carrying
        /// no caution of any kind. A person can weigh a caution; a timer cannot,
        /// so anything that would have prompted a second look is left for review.
        var unattended: [DiskItem] = []
        var isEmpty: Bool { findings.isEmpty }
    }

    struct Totals: Equatable, Sendable {
        /// Everything local evidence allows into review.
        var candidateBytes: Int64 = 0
        var candidateCount = 0
        /// The part that comes back by itself: caches, dependencies, build output.
        var regenerableBytes: Int64 = 0
        /// Held out because nothing regenerates it and no backup holds it.
        var exposedBytes: Int64 = 0
        var exposedCount = 0
        /// Candidates something is using right now.
        var inUseCount = 0
    }

    /// Ranks measured items. `evidence` is looked up per item; callers that already
    /// computed it should pass it to avoid re-classifying.
    static func rank(
        _ items: [DiskItem],
        evidence: [String: CleanupEvidence] = [:],
        signals: Signals = Signals(),
        limit: Int = 12
    ) -> Report {
        var ranked: [Finding] = [], withheld: [Finding] = []
        for item in items {
            let found = evidence[item.id] ?? CleanupEvidenceService.classify(item.url)
            let assessment = CandidateAssessment.make(item, evidence: found)
            var finding = evaluate(item, evidence: found, assessment: assessment, signals: signals)
            if !assessment.canSelect {
                finding.withheldBecause = .assessment
                withheld.append(finding)
            } else if finding.rebuild.effort == .irreplaceable && finding.backup.isUnprotected {
                finding.withheldBecause = .irreplaceableAndUnbacked
                withheld.append(finding)
            } else {
                ranked.append(finding)
            }
        }
        ranked.sort { $0.score == $1.score ? $0.item.id < $1.item.id : $0.score > $1.score }
        withheld.sort { $0.item.size == $1.item.size ? $0.item.id < $1.item.id : $0.item.size > $1.item.size }
        let shortlist = Array(ranked.prefix(max(0, limit)))
        var totals = Totals()
        for finding in ranked {
            totals.candidateBytes += finding.item.size
            totals.candidateCount += 1
            if finding.rebuild.effort <= .slow && finding.driver != .inUse { totals.regenerableBytes += finding.item.size }
            if finding.driver == .inUse { totals.inUseCount += 1 }
        }
        for finding in withheld where finding.withheldBecause == .irreplaceableAndUnbacked {
            totals.exposedBytes += finding.item.size
            totals.exposedCount += 1
        }
        let irreplaceable = (ranked + withheld).filter { $0.rebuild.effort == .irreplaceable && $0.assessment.canSelect }.map(\.item)
        var report = Report(
            findings: shortlist,
            withheld: Array(withheld.prefix(max(0, limit))),
            consideredCount: items.count,
            shortlistBytes: shortlist.reduce(0) { $0 + $1.reclaimableBytes }
        )
        report.totals = totals
        report.irreplaceable = irreplaceable
        report.regenerable = Array(ranked
            .filter { $0.rebuild.effort <= .slow && $0.driver != .inUse && $0.driver != .unverified }
            .map(\.item).sorted { $0.size > $1.size }.prefix(200))
        report.unattended = Array(ranked
            .filter { finding in
                guard finding.rebuild.effort <= .slow, !finding.needsPerson else { return false }
                guard finding.driver != .inUse, finding.driver != .unverified, finding.driver != .recentlyUsed else { return false }
                switch finding.evidence?.kind {
                case .knownCache, .buildOutput, .dependency: return true
                default: return false
                }
            }
            .map(\.item).sorted { $0.size > $1.size }.prefix(200))
        return report
    }

    // MARK: - Scoring

    /// Size matters sublinearly: a 10 GB cache outranks a 100 MB one, but not by
    /// a hundred times, or the ranking degenerates into a plain size sort.
    private static func sizeWeight(_ bytes: Int64) -> Double {
        guard bytes > 0 else { return 0 }
        let megabytes = Double(bytes) / 1_048_576
        return min(1, log10(megabytes + 1) / 4.5) // ~0 at 0 MB, 1.0 around 30 GB
    }

    /// How confidently local evidence says this regenerates. Blocked kinds never
    /// reach scoring: their assessment withholds them first.
    private static func kindWeight(_ kind: CleanupEvidenceKind?) -> Double {
        switch kind {
        case .knownCache: return 1.0
        case .buildOutput: return 0.95
        case .dependency: return 0.85
        case .gitIgnored: return 0.6
        case .unknown, .none: return 0.25
        case .projectRoot, .sourceLike, .sensitive: return 0.05
        }
    }

    /// Something rebuilt this morning is a bad suggestion however large it is.
    /// Untouched for months is the strongest local signal that nothing needs it.
    private static func stalenessWeight(_ modified: Date?, now: Date) -> Double {
        guard let modified else { return 0.5 } // unknown age is neither fresh nor stale
        let days = max(0, now.timeIntervalSince(modified) / 86_400)
        switch days {
        case ..<2: return 0.15
        case ..<14: return 0.4
        case ..<60: return 0.7
        case ..<180: return 0.9
        default: return 1.0
        }
    }

    private static func ageDays(_ modified: Date?, now: Date) -> Int? {
        guard let modified else { return nil }
        return max(0, Int(now.timeIntervalSince(modified) / 86_400))
    }

    static func isUnderActiveRoot(_ item: DiskItem, roots: Set<String>) -> Bool {
        guard !roots.isEmpty else { return false }
        let path = item.url.standardizedFileURL.path
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Whether a process holds something open *inside* this item.
    ///
    /// The direction matters. `lsof` reports working directories as well as files,
    /// so the home folder and `/` are almost always in the list; asking whether the
    /// item sits under an open path would mark everything on the disk as in use.
    /// An item is in use when an open path is the item itself or lies within it.
    static func containsOpenPath(_ item: DiskItem, openPaths: Set<String>) -> Bool {
        guard !openPaths.isEmpty else { return false }
        let path = item.url.standardizedFileURL.path
        if openPaths.contains(path) { return true }
        let prefix = path + "/"
        return openPaths.contains { $0.hasPrefix(prefix) }
    }

    private static func evaluate(_ item: DiskItem, evidence: CleanupEvidence?, assessment: CandidateAssessment, signals: Signals) -> Finding {
        let size = sizeWeight(item.size)
        let kind = kindWeight(evidence?.kind)
        let staleness = stalenessWeight(item.lastTouched, now: signals.now)
        let holdsOpenFile = containsOpenPath(item, openPaths: signals.openPaths)
        let active = isUnderActiveRoot(item, roots: signals.activeRoots) || holdsOpenFile
        let backup = signals.backupCoverage[item.id] ?? .unknown
        let extraBytes = signals.duplicateExtraBytes[item.id] ?? 0
        let days = ageDays(item.lastTouched, now: signals.now)

        // A running build or dev server makes its workspace a bad suggestion no
        // matter what the other signals say, so this demotes rather than adjusts.
        let activityFactor = active ? 0.15 : 1.0
        let duplicateBonus = extraBytes > 0 ? sizeWeight(extraBytes) * 0.6 : 0
        let rebuild = RebuildCost.forEvidence(evidence, name: item.name, url: item.url)
        // What it costs to get back is part of whether it is worth suggesting.
        // Irreplaceable storage is demoted hard: size never justifies proposing
        // something nothing can regenerate.
        let rebuildFactor: Double
        switch rebuild.effort {
        case .trivial, .quick: rebuildFactor = 1.0
        case .slow: rebuildFactor = 0.8
        case .unknown: rebuildFactor = 0.7
        case .irreplaceable: rebuildFactor = 0.25
        }

        // An incomplete measurement needs no score penalty: `CandidateAssessment`
        // already resolves it to `.measurementNeeded`, which withholds it from the
        // shortlist entirely. The caution below still travels with the finding.
        let score = (size * kind * staleness * activityFactor * rebuildFactor) + duplicateBonus

        var facts: [String] = [], cautions: [String] = []
        facts.append("\(bytes(item.size)) measured")
        if let evidence { facts.append(evidence.label + ": " + evidence.detail) }
        if let days {
            // "Touched" rather than "changed": this is the later of last write and
            // last read, so a cache read daily but never written is not called old.
            let read = item.accessed.map { modifiedDate in
                item.modified.map { modifiedDate > $0 } ?? true
            } ?? false
            let verb = read ? "read or changed" : "changed"
            facts.append(days == 0 ? "Last \(verb) today" : days == 1 ? "Last \(verb) yesterday" : "Last \(verb) \(days) days ago")
        } else {
            facts.append("No modification or access date available")
        }
        if evidence?.gitIgnored == true { facts.append("Ignored by the enclosing Git repository") }
        if let rebuild = evidence?.rebuild { facts.append("Regenerates: " + rebuild) }
        if extraBytes > 0 { facts.append("\(bytes(extraBytes)) of confirmed extra copies") }
        if rebuild.effort != .unknown { facts.append(rebuild.summary) }

        if active { cautions.append("A development process or listening port maps to this location; it is likely in use.") }
        if isUnderActiveRoot(item, roots: signals.uncommittedRoots) {
            cautions.append("The repository around this has uncommitted changes. The folder itself may be generated, but work beside it is not saved anywhere else.")
        }
        if rebuild.effort == .irreplaceable { cautions.append(rebuild.estimate) }
        if backup.isUnprotected {
            cautions.append(backup.detail)
            if rebuild.effort == .irreplaceable {
                cautions.append("Nothing regenerates this and no backup holds it. Copy it somewhere before considering removal.")
            }
        }
        if holdsOpenFile {
            cautions.append("A running process currently holds a file open here.")
        }
        if item.incomplete { cautions.append("Measurement is incomplete, so the size shown is a lower bound.") }
        if evidence?.kind == .unknown { cautions.append("No cache or generated-file evidence was found; inspect before acting.") }
        cautions.append(contentsOf: assessment.unknowns)

        let driver: Driver
        if active { driver = .inUse }
        else if duplicateBonus > 0 && duplicateBonus >= size * kind * staleness { driver = .duplicateCopies }
        else if evidence?.kind == .unknown || evidence == nil { driver = .unverified }
        else if let days, days < 2 { driver = .recentlyUsed }
        else if staleness >= 0.7 && kind >= 0.85 { driver = .staleCache }
        else { driver = .largeRebuildable }

        let beside = isUnderActiveRoot(item, roots: signals.uncommittedRoots)
        let unchecked = isUnderActiveRoot(item, roots: signals.manualOnlyRoots)
        let needsPerson = active || beside || unchecked || item.incomplete || evidence == nil || evidence?.kind == .unknown || rebuild.effort > .slow
        return Finding(
            item: item,
            assessment: assessment,
            evidence: evidence,
            score: score,
            driver: driver,
            rebuild: rebuild,
            backup: backup,
            needsPerson: needsPerson,
            headline: headline(driver, item: item, evidence: evidence, days: days, extraBytes: extraBytes),
            facts: facts,
            cautions: cautions
        )
    }

    private static func headline(_ driver: Driver, item: DiskItem, evidence: CleanupEvidence?, days: Int?, extraBytes: Int64) -> String {
        let label = evidence?.label.lowercased() ?? "storage"
        switch driver {
        case .staleCache:
            guard let days else { return "\(bytes(item.size)) of \(label) with no recent changes." }
            return "\(bytes(item.size)) of \(label), untouched for \(days) days."
        case .largeRebuildable:
            return "\(bytes(item.size)) of \(label) that local evidence says regenerates."
        case .duplicateCopies:
            return "\(bytes(extraBytes)) is duplicate copies of content kept elsewhere."
        case .recentlyUsed:
            return "\(bytes(item.size)) of \(label), but it changed in the last day."
        case .inUse:
            return "\(bytes(item.size)), and something running appears to be using it."
        case .unverified:
            return "\(bytes(item.size)) with no cache or generated-file evidence."
        }
    }
}
