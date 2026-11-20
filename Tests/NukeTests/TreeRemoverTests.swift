import XCTest
@testable import Nuke

final class TreeRemoverTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/nuke-remove-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5000).write(to: root.appendingPathComponent("a/b/f"))
        try Data(repeating: 1, count: 5000).write(to: root.appendingPathComponent("a/g"))
        return root
    }

    func testRemovesWholeTreeAndCountsBytes() throws {
        let root = try fixture()
        let result = TreeRemover.remove(root)
        XCTAssertTrue(result.rootRemoved && result.complete)
        XCTAssertGreaterThan(result.removedBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSymlinksAreRemovedNotFollowed() throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        _ = TreeRemover.remove(root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("a/b/f").path), "the link's target is untouched")
    }

    func testLockedFileIsLeftWithAdviceAndTheRestGoes() throws {
        let root = try fixture()
        let locked = root.appendingPathComponent("a/g")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path); try? FileManager.default.removeItem(at: root) }
        let result = TreeRemover.remove(root)
        XCTAssertFalse(result.complete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("a/b/f").path), "it carried on past the locked file")
        XCTAssertTrue(result.leftBehind.contains { $0.advice.contains("nouchg") }, result.leftBehind.map(\.advice).joined())
    }

    func testKeepRootEmptiesButKeepsTheFolder() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let result = TreeRemover.remove(root, keepRoot: true)
        XCTAssertTrue(result.complete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
}
