import XCTest
@testable import Nuke

final class TrashTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-trash-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testUnreadableChildLeavesVisiblePreviewAndDisablesDeletion() throws {
        let root = try fixture()
        let unreadable = root.appendingPathComponent("blocked")
        let visible = root.appendingPathComponent("visible.txt")
        let fm = FileManager.default
        try fm.createDirectory(at: unreadable, withIntermediateDirectories: false)
        try Data([1]).write(to: unreadable.appendingPathComponent("child"))
        try Data([2]).write(to: visible)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
            try? fm.removeItem(at: root)
        }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        let service = TrashService(root: root)
        let snapshot = try service.inspect()
        XCTAssertFalse(snapshot.complete)
        let entry = try XCTUnwrap(snapshot.entries.first { $0.item.name == "visible.txt" })
        XCTAssertThrowsError(try service.validate(entry, rootIdentity: snapshot.rootIdentity))
        XCTAssertTrue(fm.fileExists(atPath: visible.path))
    }

    func testDeletesOnlyReviewedItemsAndPreservesNewArrivals() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reviewed = root.appendingPathComponent("reviewed.txt")
        try Data("old".utf8).write(to: reviewed)
        let service = TrashService(root: root), snapshot = try service.inspect()
        let arrival = root.appendingPathComponent("new.txt")
        try Data("new".utf8).write(to: arrival)
        let outcomes = service.deleteReviewed(snapshot.entries, rootIdentity: snapshot.rootIdentity)
        XCTAssertTrue(outcomes.allSatisfy { $0.hasPrefix("Permanently deleted:") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: reviewed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: arrival.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }
    func testNestedChangesRefuseTheWholePlan() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let child = folder.appendingPathComponent("child.txt")
        try Data("before".utf8).write(to: child)
        try Data("keep".utf8).write(to: root.appendingPathComponent("other.txt"))
        let service = TrashService(root: root), snapshot = try service.inspect()
        try Data("after and different size".utf8).write(to: child)
        let outcomes = service.deleteReviewed(snapshot.entries, rootIdentity: snapshot.rootIdentity)
        XCTAssertTrue(outcomes[0].hasPrefix("Cleanup cancelled:"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("other.txt").path))
    }
    func testTrashedSymlinkDoesNotDeleteItsTarget() throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("keep.txt")
        try Data("keep me".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let service = TrashService(root: root), snapshot = try service.inspect()
        let outcomes = service.deleteReviewed(snapshot.entries, rootIdentity: snapshot.rootIdentity)
        XCTAssertTrue(outcomes[0].hasPrefix("Permanently deleted:"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testOutsideRootEntryIsRefused() throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let service = TrashService(root: root), snapshot = try service.inspect()
        let url = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: url)
        let entry = TrashEntry(item: DiskItem(url: url, size: 4, allocated: 4, directory: false, symlink: false, modified: nil, identity: FileIdentity.read(url), incomplete: false), fingerprint: "invalid")
        XCTAssertThrowsError(try service.validate(entry, rootIdentity: snapshot.rootIdentity))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testSymlinkTrashRootIsRefused() throws {
        let root = try fixture(), target = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: target) }
        let link = root.appendingPathComponent("fake-trash")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try TrashService(root: link).inspect())
    }
    func testDifferentRootIdentityIsRefused() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("keep".utf8).write(to: root.appendingPathComponent("file"))
        let service = TrashService(root: root), snapshot = try service.inspect()
        XCTAssertThrowsError(try service.validate(snapshot.entries[0], rootIdentity: .init(device: 0, inode: 0)))
    }
    func testEmptyTrashHasNoItems() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try TrashService(root: root).inspect()
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(snapshot.size, 0)
    }
}
