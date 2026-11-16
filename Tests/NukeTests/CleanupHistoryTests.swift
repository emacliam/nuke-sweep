import Foundation
import XCTest
@testable import Nuke

final class CleanupHistoryTests: XCTestCase {
    func testLegacyHistoryCreditsOnlyMeasuredPermanentCleanupAndSurvivesTrimming() throws {
        let successful = ReceiptItem(originalPath: "/example", trashPath: nil, size: 80,
                                     success: true, outcome: "Deleted")
        let failed = ReceiptItem(originalPath: "/other", trashPath: nil, size: 200,
                                 success: false, outcome: "Failed")
        func receipt(_ title: String, after: Int64) -> CleanupReceipt {
            CleanupReceipt(date: .now, title: title, items: [successful, failed],
                           freeBefore: 100, freeAfter: after, undo: "")
        }
        let legacy = [receipt("File cleanup", after: 200), receipt("Permanent Trash cleanup", after: 210),
                      receipt("Permanent Trash cleanup", after: 140), receipt("Permanent Trash cleanup", after: 90)]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var history = try decoder.decode(CleanupHistory.self, from: encoder.encode(legacy))
        XCTAssertEqual(history.observedFreed, 120)
        XCTAssertEqual(history.receipts.count, legacy.count)
        history.receipts.removeAll()
        let restored = try decoder.decode(CleanupHistory.self, from: encoder.encode(history))
        XCTAssertEqual(restored.observedFreed, 120)
    }
}
