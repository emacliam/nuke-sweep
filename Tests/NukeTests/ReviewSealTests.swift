import XCTest
@testable import Nuke

final class ReviewSealTests: XCTestCase {
    func fixture() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/review-seal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: root.appendingPathComponent("build/output.o"))
        return root
    }
    func testNewProtectedDescendantRefusesExecutionWithoutMoving() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("build")))
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [], openFiles: { [] }).items.first)
        try FileManager.default.createDirectory(at: item.url.appendingPathComponent(".git"), withIntermediateDirectories: true)
        var moved = false
        let receipt = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [], mover: { _ in moved = true; return nil })
        XCTAssertFalse(moved)
        XCTAssertFalse(try XCTUnwrap(receipt.items.first).success)
    }
    func testModifiedFileRequiresNewReview() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("build/output.o")))
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [], openFiles: { [] }).items.first)
        try Data([9,9,9,9]).write(to: item.url)
        var moved = false
        let result = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [], mover: { _ in moved = true; return nil })
        XCTAssertFalse(moved); XCTAssertFalse(result.items[0].success)
    }
    func testFreshReviewedItemCanMoveThroughExecutor() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("build")))
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [], openFiles: { [] }).items.first)
        var moved = false
        let result = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [], mover: { _ in moved = true; return URL(fileURLWithPath: "/test-trash/build") })
        XCTAssertTrue(moved); XCTAssertTrue(result.items[0].success)
    }
    func testMissingReviewCannotMove() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("build")))
        var moved = false
        let result = ReceiptService.moveToTrash([item], proofs: [], runningAppPaths: [], mover: { _ in moved = true; return nil })
        XCTAssertFalse(moved); XCTAssertFalse(result.items[0].success)
    }
    func testCredentialsAndSourceControlAncestorsAreProtected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for path in ["build/.env", "build/.env.production", "build/.npmrc", "build/private.pem", "build/.git/config"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
            XCTAssertTrue(CleanupSafety.isSensitive(url.path), path)
            let item = try XCTUnwrap(InventoryService.measure(url))
            XCTAssertTrue(ReviewPlanner.prepare([item], scopes: [], openFiles: { [] }).items.isEmpty, path)
        }
        XCTAssertFalse(CleanupSafety.isSensitive(root.appendingPathComponent(".env.example").path))
    }
}
