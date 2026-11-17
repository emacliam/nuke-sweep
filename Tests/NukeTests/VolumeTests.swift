import XCTest
@testable import Nuke

final class VolumeTests: XCTestCase {
    func testOrdinaryDirectoryIsNotAcceptedAsAMountedVolume() {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        XCTAssertNil(MountedVolumeService.connectedIdentity(directory))
        XCTAssertNotNil(MountedVolumeService.connectedIdentity(URL(fileURLWithPath: "/")))
    }

    func testMountedFixtureIsScannedWithoutFollowingLinks() throws {
        let path = ProcessInfo.processInfo.environment["NUKE_TEST_VOLUME_PATH"]
        try XCTSkipUnless(path != nil, "Set NUKE_TEST_VOLUME_PATH to a disposable mounted volume.")
        let root = URL(fileURLWithPath: try XCTUnwrap(path), isDirectory: true)
        let identity = try XCTUnwrap(MountedVolumeService.connectedIdentity(root))
        let result = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(result.items.first { $0.name == "fixture.bin" }?.size, 4096)
        XCTAssertEqual(result.items.first { $0.name == "outside" }?.symlink, true)
        XCTAssertEqual(MountedVolumeService.connectedIdentity(root), identity)
    }

    func testMountedVolumeListIncludesRootAndValidCapacity() {
        let volumes = MountedVolumeService.list()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.contains { $0.url.standardizedFileURL.path == "/" })
        for volume in volumes {
            XCTAssertFalse(volume.name.isEmpty)
            XCTAssertGreaterThan(volume.total, 0)
            XCTAssertGreaterThanOrEqual(volume.free, 0)
            XCTAssertLessThanOrEqual(volume.free, volume.total)
            XCTAssertTrue(FileManager.default.fileExists(atPath: volume.url.path))
        }
    }

    func testRootVolumeSortsFirst() {
        let volumes = MountedVolumeService.list()
        XCTAssertEqual(volumes.first?.isRoot, true)
    }
}
