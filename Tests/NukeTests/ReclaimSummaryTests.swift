import XCTest
@testable import Nuke

/// The aggregate the app previously never drew. Its whole value rests on being
/// honest about what it has not looked at, so these pin that distinction.
final class ReclaimSummaryTests: XCTestCase {
    private func summary(
        quick: Int64 = 0, quickMeasured: Bool = false,
        developer: Int64 = 0, developerMeasured: Bool = false,
        projects: Int64 = 0, projectsMeasured: Bool = false,
        trash: Int64? = nil,
        duplicates: Int64 = 0, duplicatesMeasured: Bool = false
    ) -> ReclaimSummary {
        .make(quickBytes: quick, quickMeasured: quickMeasured,
              developerBytes: developer, developerMeasured: developerMeasured,
              projectBytes: projects, projectsMeasured: projectsMeasured,
              trashBytes: trash,
              duplicateBytes: duplicates, duplicatesMeasured: duplicatesMeasured)
    }

    /// The failure mode this design exists to avoid: an unscanned area counted as
    /// zero produces a confident total that is simply wrong.
    func testUnmeasuredAreasAreNotCountedAsZeroInTheTotal() {
        let s = summary(quick: 5_000_000_000, quickMeasured: true)
        XCTAssertEqual(s.measuredBytes, 5_000_000_000)
        XCTAssertEqual(s.measuredAreas.count, 1)
        XCTAssertEqual(s.unmeasuredAreas.count, 4, "Everything else must be reported as unmeasured.")
    }

    func testMeasuredAreasLeadAndSortLargestFirst() {
        let s = summary(quick: 1_000_000_000, quickMeasured: true,
                        developer: 9_000_000_000, developerMeasured: true)
        let ordered = s.ordered
        XCTAssertEqual(ordered[0].id, "developer")
        XCTAssertEqual(ordered[1].id, "quick")
        XCTAssertTrue(ordered.dropFirst(2).allSatisfy { !$0.measured }, "Unmeasured areas come last.")
    }

    /// Trash is measured whenever a size exists, including a genuine zero.
    func testAnEmptyTrashCountsAsMeasuredNotAsUnknown() {
        let measured = summary(trash: 0)
        XCTAssertTrue(measured.areas.first { $0.id == "trash" }?.measured ?? false)
        let unknown = summary(trash: nil)
        XCTAssertFalse(unknown.areas.first { $0.id == "trash" }?.measured ?? true)
    }

    func testEveryAreaRoutesSomewhere() {
        let s = summary()
        XCTAssertEqual(Set(s.areas.map(\.id)).count, s.areas.count, "Area ids must be unique.")
        XCTAssertEqual(s.areas.count, 5)
        XCTAssertTrue(s.hasAnything, "An all-unmeasured summary is still worth showing: it says what to scan.")
    }

    func testATotallyMeasuredSummaryReportsNoGaps() {
        let s = summary(quick: 1, quickMeasured: true, developer: 2, developerMeasured: true,
                        projects: 3, projectsMeasured: true, trash: 4,
                        duplicates: 5, duplicatesMeasured: true)
        XCTAssertTrue(s.unmeasuredAreas.isEmpty)
        XCTAssertEqual(s.measuredBytes, 15)
    }
}
