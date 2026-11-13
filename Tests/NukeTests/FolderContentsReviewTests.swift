import Foundation
import XCTest
@testable import Nuke

final class FolderContentsReviewTests: XCTestCase {
    func testPartialFolderReviewRetainsContainerAndSeparatesProtectedChildren() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/contents-review-" + UUID().uuidString)
        let build = root.appendingPathComponent("build")
        let fm = FileManager.default
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for name in ["output.bin", "keep.bin", ".env"] {
            try Data([1]).write(to: build.appendingPathComponent(name))
        }
        let partial = DiskItem(url: build, size: 0, allocated: 0, directory: true, symlink: false,
                               modified: nil, identity: try XCTUnwrap(FileIdentity.read(build)), incomplete: true)
        let scope = DeveloperScope(label: "Fixture", path: root.path, cleanupAllowed: true, exclusions: ["build/keep.bin"])
        let review = ReviewPlanner.prepareFolderContents(partial, scopes: [], token: ScanCancellation(),
                                                         developerScopes: [scope], openFiles: { [] })
        XCTAssertEqual(review.items.map(\.name), ["output.bin"])
        XCTAssertNotNil(review.items.first?.reviewSeal)
        XCTAssertEqual(Set(review.blocked.map { $0.url.lastPathComponent }), [".env", "keep.bin"])
        XCTAssertTrue(fm.fileExists(atPath: build.path))

        try fm.moveItem(at: build, to: root.appendingPathComponent("previous-build"))
        try fm.createDirectory(at: build, withIntermediateDirectories: false)
        try Data([2]).write(to: build.appendingPathComponent("new.bin"))
        let stale = ReviewPlanner.prepareFolderContents(partial, scopes: [], token: ScanCancellation(), openFiles: { [] })
        XCTAssertTrue(stale.items.isEmpty)
        XCTAssertTrue(stale.failures.contains { $0.contains("changed") })
    }
}
