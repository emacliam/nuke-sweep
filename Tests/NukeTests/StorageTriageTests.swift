import XCTest
@testable import Nuke

/// Triage is the offline product: the ranking, the headline and every stated fact
/// must hold with no provider configured. These pin the ordering decisions that
/// make the shortlist worth reading rather than a plain size sort.
final class StorageTriageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ path: String, size: Int64, ageDays: Double?, incomplete: Bool = false) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: path),
            size: size,
            allocated: size,
            directory: true,
            symlink: false,
            modified: ageDays.map { now.addingTimeInterval(-$0 * 86_400) },
            identity: nil,
            incomplete: incomplete
        )
    }

    private func evidence(_ kind: CleanupEvidenceKind, rebuild: String? = "Rebuild from source.", gitIgnored: Bool = true) -> CleanupEvidence {
        CleanupEvidence(kind: kind, detail: "Fixture evidence.", rebuild: rebuild, gitIgnored: gitIgnored)
    }

    private func signals(
        active: Set<String> = [],
        duplicates: [String: Int64] = [:],
        uncommitted: Set<String> = [],
        open openPaths: Set<String> = [],
        backup: [String: BackupCoverage] = [:]
    ) -> StorageTriage.Signals {
        var s = StorageTriage.Signals()
        s.activeRoots = active
        s.duplicateExtraBytes = duplicates
        s.uncommittedRoots = uncommitted
        s.openPaths = openPaths
        s.backupCoverage = backup
        s.now = now
        return s
    }

    /// The quadrant that actually matters: nothing regenerates it and no backup
    /// holds it. Such an item is withheld rather than scored down — suppressing a
    /// 2 GB warning below a 2 MB cache would bury the one thing worth reading.
    func testIrreplaceableAndUnbackedIsWithheldRatherThanRanked() {
        let exposed = item("/tmp/fixture/Archives", size: 5_000_000_000, ageDays: 300)
        let covered = item("/tmp/fixture/OtherArchives", size: 5_000_000_000, ageDays: 300)
        let archiveEvidence = CleanupEvidence(kind: .buildOutput, detail: "These are products, not a cache.", rebuild: "Only a new archive build recreates these.", gitIgnored: false)
        let report = StorageTriage.rank(
            [exposed, covered],
            evidence: [exposed.id: archiveEvidence, covered.id: archiveEvidence],
            signals: signals(backup: [exposed.id: .excluded, covered.id: .included])
        )
        XCTAssertFalse(report.findings.contains { $0.item.id == exposed.id },
                       "An item with no copy anywhere must not be offered as a candidate.")
        let held = report.withheld.first { $0.item.id == exposed.id }
        XCTAssertEqual(held?.withheldBecause, .irreplaceableAndUnbacked)
        XCTAssertTrue(held?.cautions.contains { $0.contains("no backup holds it") } ?? false)
        XCTAssertTrue(report.findings.contains { $0.item.id == covered.id },
                      "The same item with a backup is still a normal candidate.")
    }

    /// Withholding must key on the pair, not on either half alone.
    func testIrreplaceableWithABackupAndRegenerableWithoutOneBothStayCandidates() {
        let archived = item("/tmp/fixture/Archives", size: 3_000_000_000, ageDays: 300)
        let cache = item("/tmp/fixture/cache", size: 3_000_000_000, ageDays: 300)
        let report = StorageTriage.rank(
            [archived, cache],
            evidence: [
                archived.id: CleanupEvidence(kind: .buildOutput, detail: "Products, not a cache.", rebuild: "Only a new archive build recreates these.", gitIgnored: false),
                cache.id: evidence(.knownCache)
            ],
            signals: signals(backup: [archived.id: .included, cache.id: .excluded])
        )
        XCTAssertEqual(report.withheld.filter { $0.withheldBecause == .irreplaceableAndUnbacked }.count, 0)
        XCTAssertEqual(report.findings.count, 2)
    }

    /// Unknown coverage is not proof of a missing backup, so it must not withhold.
    func testUnknownBackupCoverageDoesNotWithholdAnIrreplaceableItem() {
        let archive = item("/tmp/fixture/Archives", size: 3_000_000_000, ageDays: 300)
        let report = StorageTriage.rank(
            [archive],
            evidence: [archive.id: CleanupEvidence(kind: .buildOutput, detail: "Products.", rebuild: "Only a new archive build recreates these.", gitIgnored: false)],
            signals: signals(backup: [archive.id: .unknown])
        )
        XCTAssertEqual(report.findings.count, 1, "An unanswered backup question must not remove the item.")
    }

    func testAnUnansweredBackupQuestionDoesNotChangeTheRanking() {
        let a = item("/tmp/fixture/a", size: 2_000_000_000, ageDays: 100)
        let withUnknown = StorageTriage.rank([a], evidence: [a.id: evidence(.knownCache)], signals: signals(backup: [a.id: .unknown]))
        let withNothing = StorageTriage.rank([a], evidence: [a.id: evidence(.knownCache)], signals: signals())
        XCTAssertEqual(withUnknown.findings.first?.score, withNothing.findings.first?.score,
                       "Unknown coverage must be neutral, not a penalty.")
    }

    /// Review already warns about open handles. Knowing while ranking stops an
    /// in-use folder from leading the shortlist in the first place.
    func testAnOpenFileHandleDemotesAndFlagsTheItem() {
        let busy = item("/tmp/fixture/busy", size: 6_000_000_000, ageDays: 200)
        let idle = item("/tmp/fixture/idle", size: 2_000_000_000, ageDays: 200)
        let report = StorageTriage.rank(
            [busy, idle],
            evidence: [busy.id: evidence(.knownCache), idle.id: evidence(.knownCache)],
            signals: signals(open: ["/tmp/fixture/busy"])
        )
        XCTAssertEqual(report.findings.first?.item.id, idle.id)
        let flagged = report.findings.first { $0.item.id == busy.id }
        XCTAssertEqual(flagged?.driver, .inUse)
        XCTAssertTrue(flagged?.cautions.contains { $0.contains("holds a file open") } ?? false)
    }

    /// `lsof` lists working directories, so the home folder is nearly always
    /// "open". An ancestor being open says nothing about the item; the first
    /// version of this check got the direction wrong and flagged every candidate
    /// on a real Mac as in use.
    func testAnOpenAncestorDirectoryDoesNotMarkTheItemInUse() {
        let cache = item("/tmp/fixture/home/Library/Caches/tool", size: 3_000_000_000, ageDays: 200)
        let report = StorageTriage.rank(
            [cache],
            evidence: [cache.id: evidence(.knownCache)],
            signals: signals(open: ["/", "/tmp/fixture/home", "/tmp/fixture/home/Library"])
        )
        XCTAssertNotEqual(report.findings.first?.driver, .inUse)
        XCTAssertEqual(report.totals.inUseCount, 0)
        XCTAssertEqual(report.totals.regenerableBytes, 3_000_000_000)
    }

    func testAnOpenFileInsideTheItemMarksItInUse() {
        let cache = item("/tmp/fixture/cache", size: 3_000_000_000, ageDays: 200)
        let report = StorageTriage.rank(
            [cache],
            evidence: [cache.id: evidence(.knownCache)],
            signals: signals(open: ["/tmp/fixture/cache/db/index.sqlite"])
        )
        XCTAssertEqual(report.findings.first?.driver, .inUse)
        XCTAssertEqual(report.totals.regenerableBytes, 0, "Something in use is not counted as coming back by itself.")
    }

    /// A sibling sharing a name prefix is a different folder.
    func testAnOpenFileInASiblingWithASharedPrefixIsIgnored() {
        let cache = item("/tmp/fixture/cache", size: 1_000_000_000, ageDays: 200)
        let report = StorageTriage.rank(
            [cache],
            evidence: [cache.id: evidence(.knownCache)],
            signals: signals(open: ["/tmp/fixture/cache-other/file"])
        )
        XCTAssertNotEqual(report.findings.first?.driver, .inUse)
    }

    func testTotalsDescribeEveryCandidateNotOnlyTheShortlist() {
        let fixtures = (0..<30).map { item("/tmp/fixture/c\($0)", size: 100_000_000, ageDays: 200) }
        let map = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, evidence(.knownCache)) })
        let report = StorageTriage.rank(fixtures, evidence: map, signals: signals(), limit: 5)
        XCTAssertEqual(report.findings.count, 5)
        XCTAssertEqual(report.totals.candidateCount, 30)
        XCTAssertEqual(report.totals.candidateBytes, 3_000_000_000)
        XCTAssertEqual(report.regenerable.count, 30)
    }

    /// Size must not be able to justify proposing something nothing regenerates.
    func testIrreplaceableStorageIsDemotedBelowSmallerRegenerableStorage() {
        let archive = item("/tmp/fixture/Archives", size: 8_000_000_000, ageDays: 300)
        let cache = item("/tmp/fixture/node_modules", size: 3_000_000_000, ageDays: 300)
        let report = StorageTriage.rank(
            [archive, cache],
            evidence: [
                archive.id: CleanupEvidence(kind: .buildOutput, detail: "These are products, not a cache.", rebuild: "Only a new archive build recreates these. Keep any archive matching a release you still support.", gitIgnored: false),
                cache.id: evidence(.dependency)
            ],
            signals: signals()
        )
        XCTAssertEqual(report.findings.first?.item.id, cache.id,
                       "A smaller regenerable folder should outrank a larger irreplaceable one.")
    }

    func testEveryFindingCarriesARebuildCost() {
        let node = item("/tmp/fixture/node_modules", size: 2_000_000_000, ageDays: 90)
        let report = StorageTriage.rank([node], evidence: [node.id: evidence(.dependency)], signals: signals())
        let finding = report.findings.first
        XCTAssertEqual(finding?.rebuild.effort, .slow)
        XCTAssertNotNil(finding?.rebuild.action)
        XCTAssertTrue(finding?.facts.contains { $0.contains("Back in") } ?? false,
                      "The cost of getting it back belongs in the stated evidence.")
    }

    /// The folder may be generated; the work beside it is not.
    func testAnUncommittedRepositoryRaisesACautionWithoutBlockingTheItem() {
        let build = item("/tmp/fixture/app/dist", size: 1_000_000_000, ageDays: 60)
        let report = StorageTriage.rank(
            [build],
            evidence: [build.id: evidence(.buildOutput)],
            signals: signals(uncommitted: ["/tmp/fixture/app"])
        )
        let finding = report.findings.first
        XCTAssertNotNil(finding, "An uncommitted repository is a caution, not a block.")
        XCTAssertTrue(finding?.cautions.contains { $0.contains("uncommitted changes") } ?? false)
    }

    func testStaleCacheOutranksARecentlyChangedCacheOfTheSameSize() {
        let stale = item("/tmp/fixture/stale-cache", size: 4_000_000_000, ageDays: 200)
        let fresh = item("/tmp/fixture/fresh-cache", size: 4_000_000_000, ageDays: 0)
        let report = StorageTriage.rank(
            [fresh, stale],
            evidence: [stale.id: evidence(.knownCache), fresh.id: evidence(.knownCache)],
            signals: signals()
        )
        XCTAssertEqual(report.findings.first?.item.id, stale.id, "A 200-day-old cache should outrank an identical one changed today.")
        XCTAssertEqual(report.findings.first?.driver, .staleCache)
        XCTAssertEqual(report.findings.last?.driver, .recentlyUsed)
    }

    /// Size is deliberately sublinear: evidence quality has to be able to beat raw bytes.
    func testStrongEvidenceBeatsAModestlyLargerUnknownItem() {
        let cache = item("/tmp/fixture/cache", size: 3_000_000_000, ageDays: 90)
        let mystery = item("/tmp/fixture/mystery", size: 6_000_000_000, ageDays: 90)
        let report = StorageTriage.rank(
            [mystery, cache],
            evidence: [cache.id: evidence(.knownCache), mystery.id: evidence(.unknown, rebuild: nil, gitIgnored: false)],
            signals: signals()
        )
        XCTAssertEqual(report.findings.first?.item.id, cache.id, "A well-evidenced cache should outrank a larger unexplained folder.")
        XCTAssertEqual(report.findings.last?.driver, .unverified)
    }

    func testAnItemUnderAnActiveProjectRootIsDemotedAndFlagged() {
        let busy = item("/tmp/fixture/app/node_modules", size: 5_000_000_000, ageDays: 120)
        let idle = item("/tmp/fixture/other/node_modules", size: 1_000_000_000, ageDays: 120)
        let report = StorageTriage.rank(
            [busy, idle],
            evidence: [busy.id: evidence(.dependency), idle.id: evidence(.dependency)],
            signals: signals(active: ["/tmp/fixture/app"])
        )
        XCTAssertEqual(report.findings.first?.item.id, idle.id, "A workspace with something running should not lead the shortlist.")
        let demoted = report.findings.first { $0.item.id == busy.id }
        XCTAssertEqual(demoted?.driver, .inUse)
        XCTAssertTrue(demoted?.cautions.contains { $0.contains("in use") } ?? false)
    }

    func testProtectedItemsAreWithheldFromTheShortlistRatherThanRanked() {
        let source = item("/tmp/fixture/project/src", size: 9_000_000_000, ageDays: 300)
        let cache = item("/tmp/fixture/cache", size: 1_000_000, ageDays: 300)
        let report = StorageTriage.rank(
            [source, cache],
            evidence: [source.id: evidence(.sourceLike, rebuild: nil, gitIgnored: false), cache.id: evidence(.knownCache)],
            signals: signals()
        )
        XCTAssertFalse(report.findings.contains { $0.item.id == source.id }, "A source-like item must never enter the actionable shortlist.")
        XCTAssertTrue(report.withheld.contains { $0.item.id == source.id }, "It should still be reported as withheld, not silently dropped.")
        XCTAssertEqual(report.findings.map(\.item.id), [cache.id])
    }

    func testDuplicateCopiesRaiseAnItemAndBecomeItsHeadline() {
        let plain = item("/tmp/fixture/plain", size: 2_000_000_000, ageDays: 30)
        let duped = item("/tmp/fixture/duped", size: 2_000_000_000, ageDays: 30)
        let report = StorageTriage.rank(
            [plain, duped],
            evidence: [plain.id: evidence(.gitIgnored), duped.id: evidence(.gitIgnored)],
            signals: signals(duplicates: [duped.id: 1_500_000_000])
        )
        XCTAssertEqual(report.findings.first?.item.id, duped.id)
        XCTAssertEqual(report.findings.first?.driver, .duplicateCopies)
        XCTAssertTrue(report.findings.first?.headline.contains("duplicate copies") ?? false)
    }

    /// An unmeasured item cannot be ranked honestly, because the size driving the
    /// rank is only a lower bound. It is withheld rather than demoted, and says why.
    func testIncompleteMeasurementIsWithheldAndDisclosed() {
        let partial = item("/tmp/fixture/partial", size: 8_000_000_000, ageDays: 100, incomplete: true)
        let complete = item("/tmp/fixture/complete", size: 4_000_000_000, ageDays: 100)
        let report = StorageTriage.rank(
            [partial, complete],
            evidence: [partial.id: evidence(.knownCache), complete.id: evidence(.knownCache)],
            signals: signals()
        )
        XCTAssertEqual(report.findings.map(\.item.id), [complete.id], "Only the trustworthy measurement belongs in the shortlist.")
        let flagged = report.withheld.first { $0.item.id == partial.id }
        XCTAssertEqual(flagged?.assessment.state, .measurementNeeded)
        XCTAssertTrue(flagged?.cautions.contains { $0.contains("lower bound") } ?? false)
    }

    /// The whole point of triage is that it works with AI off.
    func testRankingIsDeterministicAndNeedsNoProvider() {
        let fixtures = (0..<40).map { item("/tmp/fixture/item-\($0)", size: Int64($0) * 100_000_000 + 1, ageDays: Double($0 * 5)) }
        let map = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, evidence(.knownCache)) })
        let first = StorageTriage.rank(fixtures, evidence: map, signals: signals(), limit: 10)
        let second = StorageTriage.rank(fixtures.reversed(), evidence: map, signals: signals(), limit: 10)
        XCTAssertEqual(first.findings.map(\.item.id), second.findings.map(\.item.id), "Ranking must not depend on input order.")
        XCTAssertEqual(first.findings.count, 10)
        XCTAssertEqual(first.consideredCount, 40)
        XCTAssertEqual(first.shortlistBytes, first.findings.reduce(0) { $0 + $1.item.size })
    }

    func testEveryFindingCarriesLocalFactsAndNoSafetyGuarantee() throws {
        let fixtures = [
            item("/tmp/fixture/a", size: 2_000_000_000, ageDays: 10),
            item("/tmp/fixture/b", size: 900_000_000, ageDays: 400)
        ]
        let map = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, evidence(.buildOutput)) })
        let report = StorageTriage.rank(fixtures, evidence: map, signals: signals())
        XCTAssertEqual(report.findings.count, 2)
        for finding in report.findings {
            XCTAssertFalse(finding.facts.isEmpty, "A ranked item must show the evidence behind its rank.")
            XCTAssertFalse(finding.headline.isEmpty)
            XCTAssertFalse(finding.cautions.isEmpty, "Unknowns stay visible even for well-evidenced items.")
            XCTAssertNoThrow(try AIOutputLimits.advice(finding.headline), "Local copy must not claim anything is safe to delete.")
            for fact in finding.facts { XCTAssertNoThrow(try AIOutputLimits.advice(fact)) }
        }
    }
}
