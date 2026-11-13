import XCTest
@testable import Nuke

final class VolumeTests: XCTestCase {
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
