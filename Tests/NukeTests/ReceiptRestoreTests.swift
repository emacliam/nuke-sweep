import Darwin
import Foundation
import XCTest
@testable import Nuke

final class ReceiptRestoreTests: XCTestCase {
    func testReviewedMoveThroughSystemTrashAndRestore() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NUKE_TEST_SYSTEM_TRASH"] == "1",
                          "Opt in to exercising macOS Trash with a disposable fixture.")
        let manager = FileManager.default
        let trashDirectory = manager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let trashDescriptor = open(trashDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try XCTSkipUnless(trashDescriptor >= 0, "The test process needs access to open the macOS Trash directory.")
        close(trashDescriptor)
        let buildDirectory = URL(fileURLWithPath: manager.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath()
        let root = buildDirectory.appendingPathComponent("nuke-system-trash-" + UUID().uuidString)
        let original = root.appendingPathComponent(root.lastPathComponent + ".bin")
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            if manager.fileExists(atPath: original.path) { try? manager.removeItem(at: original) }
            _ = rmdir(root.path)
        }
        let payload = Data([1, 2, 3])
        try payload.write(to: original)
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let measured = try XCTUnwrap(InventoryService.measure(original))
        let preparation = ReviewPlanner.prepare([measured], scopes: [scope], openFiles: { [] })
        let reviewed = try XCTUnwrap(preparation.items.first, preparation.failures.joined(separator: "\n"))
        let receipt = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [], allowedRoots: [scope])
        let moved = try XCTUnwrap(receipt.items.first)
        XCTAssertTrue(moved.success, moved.outcome)
        let trashed = URL(fileURLWithPath: try XCTUnwrap(moved.trashPath, moved.outcome))
        XCTAssertFalse(manager.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: trashed), payload)
        XCTAssertNoThrow(try ReceiptRestore.restore(moved), "Restore the system Trash receipt")
        XCTAssertEqual(try Data(contentsOf: original), payload)
        XCTAssertFalse(manager.fileExists(atPath: trashed.path))
    }

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
