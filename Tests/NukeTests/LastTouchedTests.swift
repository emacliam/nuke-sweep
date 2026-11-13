import XCTest
@testable import Nuke

/// A package cache can be read on every build for a year without being written
/// once. Judging dormancy by modification time alone calls that dead weight,
/// which is the wrong answer in the one direction that costs the user something.
final class LastTouchedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(modified: Double?, accessed: Double?) -> DiskItem {
        DiskItem(
            url: URL(fileURLWithPath: "/tmp/fixture/item"),
            size: 1_000_000, allocated: 1_000_000,
            directory: true, symlink: false,
            modified: modified.map { now.addingTimeInterval(-$0 * 86_400) },
            accessed: accessed.map { now.addingTimeInterval(-$0 * 86_400) },
            identity: nil, incomplete: false
        )
    }

    func testARecentReadBeatsAnOldWrite() {
        let touched = item(modified: 400, accessed: 2).lastTouched
        XCTAssertEqual(touched, now.addingTimeInterval(-2 * 86_400),
                       "A file read two days ago is not dormant, however old its last write.")
    }

    /// Some volumes mount noatime, and a freshly written file can carry an older
    /// atime. The later of the two is correct in both directions.
    func testARecentWriteBeatsAnOldRead() {
        let touched = item(modified: 1, accessed: 500).lastTouched
        XCTAssertEqual(touched, now.addingTimeInterval(-1 * 86_400))
    }

    func testEitherDateAloneIsStillAnAnswer() {
        XCTAssertEqual(item(modified: 10, accessed: nil).lastTouched, now.addingTimeInterval(-10 * 86_400))
        XCTAssertEqual(item(modified: nil, accessed: 10).lastTouched, now.addingTimeInterval(-10 * 86_400))
    }

    func testNoDatesAtAllIsUnknownNotAncient() {
        XCTAssertNil(item(modified: nil, accessed: nil).lastTouched)
    }

    /// Ranking must follow the combined signal, not the write date.
    func testTriageTreatsAFrequentlyReadCacheAsActive() {
        let read = item(modified: 400, accessed: 1)
        let dormant = DiskItem(
            url: URL(fileURLWithPath: "/tmp/fixture/dormant"),
            size: 1_000_000, allocated: 1_000_000, directory: true, symlink: false,
            modified: now.addingTimeInterval(-400 * 86_400),
            accessed: now.addingTimeInterval(-400 * 86_400),
            identity: nil, incomplete: false
        )
        let evidence = CleanupEvidence(kind: .knownCache, detail: "Fixture.", rebuild: "Rebuilt.", gitIgnored: true)
        var signals = StorageTriage.Signals(); signals.now = now
        let report = StorageTriage.rank(
            [read, dormant],
            evidence: [read.id: evidence, dormant.id: evidence],
            signals: signals
        )
        XCTAssertEqual(report.findings.first?.item.id, dormant.id,
                       "The genuinely dormant cache should outrank one read yesterday.")
        XCTAssertEqual(report.findings.first { $0.item.id == read.id }?.driver, .recentlyUsed)
    }

    /// A date that came from the read clock should say so rather than claiming
    /// the file was modified.
    func testCopyDistinguishesAReadFromAWrite() {
        let read = item(modified: 400, accessed: 3)
        let evidence = CleanupEvidence(kind: .knownCache, detail: "Fixture.", rebuild: "Rebuilt.", gitIgnored: true)
        var signals = StorageTriage.Signals(); signals.now = now
        let report = StorageTriage.rank([read], evidence: [read.id: evidence], signals: signals)
        XCTAssertTrue(report.findings.first?.facts.contains { $0.contains("read or changed") } ?? false)
    }
}
