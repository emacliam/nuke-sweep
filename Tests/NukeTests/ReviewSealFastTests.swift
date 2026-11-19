import XCTest
import CoreServices
@testable import Nuke

final class ReviewSealFastTests: XCTestCase {
    private func fixture() throws -> (root: URL, folder: DiskItem, scope: CleanupScope) {
        let root = URL(fileURLWithPath: "/tmp/nuke-seal-" + UUID().uuidString)
        let folder = root.appendingPathComponent("app/node_modules")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("pkg"), withIntermediateDirectories: true)
        for index in 0..<50 { try Data(repeating: 1, count: 100).write(to: folder.appendingPathComponent("pkg/f\(index).js")) }
        let item = try XCTUnwrap(InventoryService.measure(folder))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        // Let the fixture's own writes reach the change record first; otherwise
        // they can land just after the review starts and look like a change
        // (which is safe, only slower: the move then reads the folder in full).
        _ = FSEventsHistory.changes(since: FSEventsGetCurrentEventId(), under: [FSEventsHistory.canonical(root.path)])
        return (root, item, scope)
    }

    func testUntouchedFolderNeedsNoSecondRead() throws {
        let (root, item, scope) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let prepared = ReviewPlanner.prepare([item], scopes: [scope], openFiles: { [] })
        let reviewed = try XCTUnwrap(prepared.items.first, prepared.failures.joined())
        XCTAssertNotNil(reviewed.reviewEventID)
        XCTAssertEqual(ReviewSeal.unchangedSinceReview([reviewed]), [reviewed.id])
        XCTAssertNoThrow(try ReviewSeal.validate(reviewed, unchangedSinceReview: true))
    }

    func testChangedFolderFallsBackToFullCompareAndIsRefused() throws {
        let (root, item, scope) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [scope], openFiles: { [] }).items.first)
        try Data([9]).write(to: item.url.appendingPathComponent("pkg/added.js"))
        let unchanged = ReviewSeal.unchangedSinceReview([reviewed])
        XCTAssertFalse(unchanged.contains(reviewed.id), "the change record shows the new file")
        XCTAssertThrowsError(try ReviewSeal.validate(reviewed, unchangedSinceReview: unchanged.contains(reviewed.id)))
    }

    func testKeyLikeFilesInsidePackageCachesAreNotPersonalData() {
        let home = "/Users/someone"
        XCTAssertFalse(CleanupSafety.isSensitive(home + "/Library/Caches/Yarn/v6/npm-react-native/template/android/app/debug.keystore", home: home))
        XCTAssertFalse(CleanupSafety.isSensitive(home + "/.npm/_cacache/content-v2/x/test.pem", home: home))
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/projects/app/android/app/release.keystore", home: home))
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/.ssh/id_ed25519", home: home))
    }
}
