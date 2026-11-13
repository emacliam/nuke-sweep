import Foundation
import XCTest
@testable import Nuke

final class ReceiptRestoreTests: XCTestCase {
    func testReviewedMoveRecordsRestorableEvidence() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/restore-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("output.bin")
        let trash = root.appendingPathComponent("trash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: false)
        try Data([1, 2, 3]).write(to: original)
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let item = try XCTUnwrap(InventoryService.measure(original))
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [scope], openFiles: { [] }).items.first)
        let receipt = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [], allowedRoots: [scope]) { source in
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try fm.moveItem(at: source, to: destination)
            return destination
        }
        let saved = try JSONDecoder().decode(CleanupReceipt.self, from: JSONEncoder().encode(receipt))
        try ReceiptRestore.restore(try XCTUnwrap(saved.items.first))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }

    func testRestoreRefusesChangedParentAndOccupiedDestinationThenRestores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originalParent = root.appendingPathComponent("original")
        let trashParent = root.appendingPathComponent("trash")
        let fm = FileManager.default
        try fm.createDirectory(at: originalParent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: trashParent, withIntermediateDirectories: true)
        let original = originalParent.appendingPathComponent("output")
        let trashed = trashParent.appendingPathComponent("output")
        let payload = Data([1, 2, 3])
        try payload.write(to: trashed)
        let evidence = RestoreEvidence(originalParent: try XCTUnwrap(FileIdentity.read(originalParent)),
                                       trashParent: try XCTUnwrap(FileIdentity.read(trashParent)),
                                       trashedItem: try XCTUnwrap(FileIdentity.read(trashed)))
        let receipt = ReceiptItem(originalPath: original.path, trashPath: trashed.path, size: 3, success: true,
                                  outcome: "Moved to Trash", restoreEvidence: evidence)

        let parked = root.appendingPathComponent("parked")
        try fm.moveItem(at: originalParent, to: parked)
        try fm.createDirectory(at: originalParent, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ReceiptRestore.restore(receipt))
        XCTAssertEqual(try Data(contentsOf: trashed), payload)
        try fm.removeItem(at: originalParent)
        try fm.moveItem(at: parked, to: originalParent)

        let movedCopy = trashParent.appendingPathComponent("old")
        try fm.moveItem(at: trashed, to: movedCopy)
        try Data([4]).write(to: trashed)
        XCTAssertThrowsError(try ReceiptRestore.restore(receipt))
        XCTAssertEqual(try Data(contentsOf: trashed), Data([4]))
        try fm.removeItem(at: trashed)
        try fm.moveItem(at: movedCopy, to: trashed)

        try Data([9]).write(to: original)
        XCTAssertThrowsError(try ReceiptRestore.restore(receipt))
        XCTAssertEqual(try Data(contentsOf: original), Data([9]))
        try fm.removeItem(at: original)
        try ReceiptRestore.restore(receipt)
        XCTAssertEqual(try Data(contentsOf: original), payload)
        XCTAssertFalse(fm.fileExists(atPath: trashed.path))
        XCTAssertThrowsError(try ReceiptRestore.restore(receipt))
    }
}
