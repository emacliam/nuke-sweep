import XCTest
@testable import Nuke

final class MonthlyReportTests: XCTestCase {
    func testReportUsesComparableChecksAndSeparatesTrashMovesFromFreeSpace() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(30 * 86_400)
        func check(_ offset: TimeInterval, _ size: Int64, coverage: Int = 2) -> FullCheckRecord {
            FullCheckRecord(date: start.addingTimeInterval(offset), regenerableBytes: size,
                            candidateBytes: size, sizes: ["/example/cache": size],
                            measuredProjects: true, coverage: coverage)
        }
        let moved = ReceiptItem(originalPath: "/example/cache", trashPath: "/example/trash", size: 75,
                                success: true, outcome: "Moved")
        let deleted = ReceiptItem(originalPath: "/example/trash", trashPath: nil, size: 75,
                                  success: true, outcome: "Deleted")
        let receipts = [
            CleanupReceipt(date: start, title: "Automatic cleanup", items: [moved], freeBefore: 10, freeAfter: 100, undo: ""),
            CleanupReceipt(date: start, title: "Permanent Trash cleanup", items: [deleted], freeBefore: 10, freeAfter: 60, undo: ""),
            CleanupReceipt(date: end, title: "Permanent Trash cleanup", items: [deleted], freeBefore: 10, freeAfter: 60, undo: "")
        ]
        let report = MonthlyReport(period: DateInterval(start: start, end: end),
                                   checks: [check(0, 10, coverage: 1), check(1, 20), check(2, 55)],
                                   receipts: receipts)
        XCTAssertEqual(report.freed, 50)
        XCTAssertEqual(report.automaticMoved, 75)
        XCTAssertEqual(report.growers.map(\.delta), [35])
        XCTAssertEqual(report.receiptCount, 2)
    }
}
