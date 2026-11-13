import XCTest
@testable import Nuke

final class CleanupBasketTests: XCTestCase {
    func item(_ path: String, directory: Bool = false) -> DiskItem {
        .init(url: URL(fileURLWithPath: path), size: 10, allocated: 10, directory: directory, symlink: false, modified: nil, identity: nil, incomplete: false)
    }
    func testCollectsAcrossFoldersAndNormalizesOverlaps() throws {
        var basket = CleanupBasket()
        try basket.add([item("/tmp/project-a/build/a"), item("/tmp/project-b/cache")])
        try basket.add([item("/tmp/project-a/build", directory: true)])
        XCTAssertEqual(basket.items.map(\.url.path), ["/tmp/project-a/build", "/tmp/project-b/cache"])
        try basket.add([item("/tmp/project-b/cache")]); XCTAssertEqual(basket.items.count, 2)
        basket.removeMoved(["/tmp/project-a/build"])
        XCTAssertEqual(basket.items.map(\.url.path), ["/tmp/project-b/cache"])
    }
    func testKeeperAndParentConflictsAreAtomic() throws {
        let keeper = item("/tmp/keepers/one"), copy = item("/tmp/copies/one")
        let proof = DuplicateProof(keeper: keeper, duplicate: copy)
        var basket = CleanupBasket(); try basket.add([copy], proofs: [proof])
        XCTAssertThrowsError(try basket.add([item("/tmp/keepers", directory: true)]))
        XCTAssertEqual(basket.items.map(\.id), [copy.id]); XCTAssertEqual(basket.proofs.count, 1)
        basket.remove(copy.id); XCTAssertTrue(basket.proofs.isEmpty)
        try basket.add([keeper]); XCTAssertThrowsError(try basket.add([copy], proofs: [proof]))
        XCTAssertEqual(basket.items.map(\.id), [keeper.id])
    }
    func testCapacityFailureDoesNotDropExistingSelection() throws {
        var basket = CleanupBasket(); try basket.add([item("/tmp/original")])
        XCTAssertThrowsError(try basket.add((0..<1000).map { item("/tmp/new-\($0)") }))
        XCTAssertEqual(basket.items.map(\.url.path), ["/tmp/original"])
    }
}

extension CleanupBasketTests {
    func testExecutorRefusesASelectedAncestorOfDuplicateKeeperBeforeMoving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-basket-executor-" + UUID().uuidString)
        let keepFolder = root.appendingPathComponent("keep"), copyFolder = root.appendingPathComponent("copies")
        try FileManager.default.createDirectory(at: keepFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = keepFolder.appendingPathComponent("a.bin"), copy = copyFolder.appendingPathComponent("b.bin")
        try Data([1,2,3]).write(to: keep); try Data([1,2,3]).write(to: copy)
        let keeper = try XCTUnwrap(InventoryService.measure(keep)), duplicate = try XCTUnwrap(InventoryService.measure(copy))
        let parent = try XCTUnwrap(InventoryService.measure(keepFolder))
        var moves = 0
        let receipt = ReceiptService.moveToTrash([parent, duplicate], proofs: [.init(keeper:keeper, duplicate:duplicate)], runningAppPaths: []) { _ in moves += 1; return nil }
        XCTAssertEqual(moves, 0)
        XCTAssertTrue(receipt.items.allSatisfy { !$0.success })
        XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path))
    }
}
