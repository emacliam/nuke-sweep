import XCTest
@testable import Nuke

/// The whole-Mac check ends on a headline figure. These pin the two ways that
/// figure could mislead: counting a location twice, and interrupting someone
/// about a change too small to matter.
final class FullCheckTests: XCTestCase {
    private func item(_ path: String, size: Int64) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), size: size, allocated: size, directory: true,
                 symlink: false, modified: nil, identity: nil, incomplete: false)
    }
    private func record(daysAgo: Double, regenerable: Int64) -> FullCheckRecord {
        FullCheckRecord(date: Date().addingTimeInterval(-daysAgo * 86_400), regenerableBytes: regenerable, candidateBytes: regenerable)
    }

    func testTheSameLocationFromTwoScansIsCountedOnce() {
        let merged = FullCheckHistory.merge([item("/tmp/f/pip", size: 500), item("/tmp/f/pip", size: 500)])
        XCTAssertEqual(merged.count, 1)
    }

    func testAnItemNestedInsideAnotherMeasuredItemIsDropped() {
        let merged = FullCheckHistory.merge([item("/tmp/f/Caches", size: 900), item("/tmp/f/Caches/pip", size: 500)])
        XCTAssertEqual(merged.map(\.url.path), ["/tmp/f/Caches"], "The inner folder is already inside the outer total.")
    }

    func testSiblingsWithASharedPrefixAreBothKept() {
        let merged = FullCheckHistory.merge([item("/tmp/f/build", size: 1), item("/tmp/f/build-cache", size: 1)])
        XCTAssertEqual(merged.count, 2)
    }

    func testEmptyLocationsAreNotCarriedIntoTheRanking() {
        XCTAssertTrue(FullCheckHistory.merge([item("/tmp/f/empty", size: 0)]).isEmpty)
    }

    func testWeeklyCheckIsOffUnlessSwitchedOn() {
        XCTAssertFalse(FullCheckHistory.isDue(last: nil, enabled: false))
        XCTAssertFalse(FullCheckHistory.isDue(last: record(daysAgo: 30, regenerable: 1), enabled: false))
    }

    func testWeeklyCheckIsDueAfterSevenDaysAndNotBefore() {
        XCTAssertTrue(FullCheckHistory.isDue(last: nil, enabled: true))
        XCTAssertFalse(FullCheckHistory.isDue(last: record(daysAgo: 3, regenerable: 1), enabled: true))
        XCTAssertTrue(FullCheckHistory.isDue(last: record(daysAgo: 8, regenerable: 1), enabled: true))
    }

    /// Caches breathe by hundreds of megabytes a day; that is not news.
    func testSmallGrowthDoesNotInterrupt() {
        let before = record(daysAgo: 7, regenerable: 10_000_000_000)
        let after = record(daysAgo: 0, regenerable: 10_400_000_000)
        XCTAssertFalse(FullCheckHistory.shouldNotify(previous: before, current: after))
    }

    func testNotableGrowthInterruptsAndShrinkingNeverDoes() {
        let before = record(daysAgo: 7, regenerable: 10_000_000_000)
        XCTAssertTrue(FullCheckHistory.shouldNotify(previous: before, current: record(daysAgo: 0, regenerable: 14_000_000_000)))
        XCTAssertFalse(FullCheckHistory.shouldNotify(previous: before, current: record(daysAgo: 0, regenerable: 2_000_000_000)))
    }

    func testChangeSentenceNamesDirectionAndIsSilentWithoutAPreviousCheck() {
        let before = record(daysAgo: 7, regenerable: 10_000_000_000)
        XCTAssertNil(FullCheckHistory.change(previous: nil, current: before))
        XCTAssertTrue(FullCheckHistory.change(previous: before, current: record(daysAgo: 0, regenerable: 15_000_000_000))?.contains("more than") ?? false)
        XCTAssertTrue(FullCheckHistory.change(previous: before, current: record(daysAgo: 0, regenerable: 3_000_000_000))?.contains("less than") ?? false)
        XCTAssertTrue(FullCheckHistory.change(previous: before, current: record(daysAgo: 0, regenerable: 10_100_000_000))?.contains("About the same") ?? false)
    }

    // MARK: - Scheduled scan digest

    private func scan(_ sizes: [String: Int64], daysAgo: Double) -> StoredScan {
        StoredScan(date: Date().addingTimeInterval(-daysAgo * 86_400), root: "/tmp/f", sizes: sizes, categories: [:])
    }
    private func result(_ sizes: [String: Int64]) -> ScanResult {
        ScanResult(items: sizes.map { item("/tmp/f/" + $0.key, size: $0.value) }, skipped: 0, visited: sizes.count, limited: false)
    }
    private func evidence(_ kind: CleanupEvidenceKind) -> CleanupEvidence {
        CleanupEvidence(kind: kind, detail: "Fixture.", rebuild: nil, gitIgnored: false)
    }

    func testDigestNamesGrowthAndTheRegenerablePart() {
        let before = scan(["node_modules": 1_000_000_000, "src": 500_000_000], daysAgo: 7)
        let after = result(["node_modules": 4_000_000_000, "src": 1_500_000_000])
        let sentence = GrowthDigest.sentence(previous: before, current: after) { item in
            self.evidence(item.name == "node_modules" ? .dependency : .sourceLike)
        }
        XCTAssertTrue(sentence?.contains("Grew") ?? false)
        XCTAssertTrue(sentence?.contains("regenerates by itself") ?? false)
    }

    func testDigestIsSilentWithoutAPreviousScanOrMeaningfulGrowth() {
        let after = result(["a": 4_000_000_000])
        XCTAssertNil(GrowthDigest.sentence(previous: nil, current: after) { _ in self.evidence(.knownCache) })
        let before = scan(["a": 3_900_000_000], daysAgo: 7)
        XCTAssertNil(GrowthDigest.sentence(previous: before, current: after) { _ in self.evidence(.knownCache) })
    }

    /// Growth in source is growth, but it must not be described as regenerable.
    func testGrowthInSourceIsNotCalledRegenerable() {
        let before = scan(["src": 1_000_000_000], daysAgo: 7)
        let after = result(["src": 5_000_000_000])
        let sentence = GrowthDigest.sentence(previous: before, current: after) { _ in self.evidence(.sourceLike) }
        XCTAssertNotNil(sentence)
        XCTAssertFalse(sentence?.contains("regenerates") ?? true)
    }
}
