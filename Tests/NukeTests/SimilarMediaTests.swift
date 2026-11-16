import Foundation
import XCTest
@testable import Nuke

final class SimilarMediaTests: XCTestCase {
    func testScannerSkipsPhotoLibrariesAndSymbolicLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = root.appendingPathComponent("Family.PHOTOSLIBRARY")
        let originals = library.appendingPathComponent("originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let protected = originals.appendingPathComponent("protected.jpg")
        try Data("Protected".utf8).write(to: protected)
        try Data("Unreadable image".utf8).write(to: root.appendingPathComponent("loose.jpg"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.jpg"), withDestinationURL: protected)

        let result = await SimilarMedia.scan(root, token: ScanCancellation())
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.compared, 0)
        XCTAssertTrue(result.matches.isEmpty)
        let direct = await SimilarMedia.scan(originals, token: ScanCancellation())
        XCTAssertTrue(direct.partial)
        XCTAssertEqual(direct.skipped, 0)
    }
}
