import XCTest
@testable import Nuke

/// Runs against a small disk image mounted for the test, never a real drive,
/// and a stand-in for Trash, never the real one.
final class OffloadTests: XCTestCase {
    private var mount: URL!
    private var image: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: "/tmp/nuke-offload-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        image = base.appendingPathComponent("drive.dmg"); mount = base.appendingPathComponent("drive")
        let create = CommandRunner.run("/usr/bin/hdiutil", ["create", "-size", "20m", "-fs", "APFS", "-volname", "NukeTest", "-quiet", image.path], timeout: 60)
        try XCTSkipIf(create.status != 0, "hdiutil unavailable: \(create.output)")
        let attach = CommandRunner.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-quiet", "-mountpoint", mount.path, image.path], timeout: 60)
        try XCTSkipIf(attach.status != 0, "could not mount the test image")
    }

    override func tearDown() {
        _ = CommandRunner.run("/usr/bin/hdiutil", ["detach", "-force", "-quiet", mount.path], timeout: 60)
        try? FileManager.default.removeItem(at: image.deletingLastPathComponent())
    }

    private func source() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/nuke-offload-src-" + UUID().uuidString + "/Project")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 300_000).write(to: root.appendingPathComponent("a/video.mov"))
        try Data("key".utf8).write(to: root.appendingPathComponent("debug.keystore"))
        return root
    }

    func testCopyVerifyThenTrashAndRestore() throws {
        let src = try source(); defer { try? FileManager.default.removeItem(at: src.deletingLastPathComponent()) }
        var trashed: URL?
        let record = try OffloadEngine.offload(src, to: mount, log: false, trash: { trashed = $0; try FileManager.default.removeItem(at: $0) })
        XCTAssertEqual(trashed, src, "the original goes to Trash only after the copy verified")
        XCTAssertEqual(record.files, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.appendingPathComponent("Project/a/video.mov").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.appendingPathComponent("Project.nuke-offload.json").path))
        let back = try OffloadEngine.restore(record, log: false)
        XCTAssertEqual(try Data(contentsOf: back.appendingPathComponent("a/video.mov")).count, 300_000)
    }

    func testSameVolumeIsRefusedAndOriginalKept() throws {
        let src = try source(); defer { try? FileManager.default.removeItem(at: src.deletingLastPathComponent()) }
        XCTAssertThrowsError(try OffloadEngine.offload(src, to: src.deletingLastPathComponent(), log: false, trash: { _ in XCTFail("must not trash") }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }
}
