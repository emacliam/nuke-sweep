import XCTest
@testable import Nuke

final class LiveWatchTests: XCTestCase {
    @MainActor func testReviewDropsGoneItemsAndHoldsChangedOnes() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-live-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gone = root.appendingPathComponent("gone"), changed = root.appendingPathComponent("changed")
        for url in [gone, changed] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1]).write(to: url.appendingPathComponent("f"))
        }
        let model = AppModel(restoring: false)
        let items = try [gone, changed].map { try XCTUnwrap(InventoryService.measure($0)) }
        model.pendingTrash = items
        model.pendingTrashSelection = Set(items.map(\.id))
        try FileManager.default.removeItem(at: gone)
        try Data([2, 3]).write(to: changed.appendingPathComponent("g"))
        model.reviewItemsChanged(items)
        XCTAssertEqual(model.pendingTrash.map(\.name), ["changed"], "a deleted item leaves the review")
        XCTAssertEqual(model.pendingChanged, [items[1].id])
        XCTAssertTrue(model.pendingTrashSelection.isEmpty, "a changed item is unticked until checked again")
    }
}
