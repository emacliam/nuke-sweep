import XCTest
@testable import Nuke

final class DuplicateBudgetTests: XCTestCase {
    func fixture(_ values: [Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-duplicate-budget-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (index, data) in values.enumerated() { try data.write(to: root.appendingPathComponent("file-\(index)")) }
        return root
    }
    func testSharedReadLimitNeverProducesUnverifiedGroups() throws {
        let root = try fixture([Data(repeating: 1, count: 8192), Data(repeating: 1, count: 8192)])
        defer { try? FileManager.default.removeItem(at: root) }
        let report = DuplicateFinder.find(root, token: ScanCancellation(), limits: .init(bytes: 10_000))
        XCTAssertLessThanOrEqual(report.bytesRead, 10_000)
        XCTAssertTrue(report.limited)
        XCTAssertEqual(report.stopReason, "File-read limit reached")
        XCTAssertTrue(report.groups.isEmpty)
    }
    func testPrefixFilterAvoidsFullReadsForDifferentFilesOfSameSize() throws {
        let root = try fixture([Data(repeating: 1, count: 100_000), Data(repeating: 2, count: 100_000)])
        defer { try? FileManager.default.removeItem(at: root) }
        let report = DuplicateFinder.find(root, token: ScanCancellation())
        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertEqual(report.bytesRead, 8192)
        XCTAssertFalse(report.limited)
    }
    func testExpiredDeadlineIsPartialWithoutReadingContents() throws {
        let root = try fixture([Data([1]), Data([1])]); defer { try? FileManager.default.removeItem(at: root) }
        let report = DuplicateFinder.find(root, token: ScanCancellation(), limits: .init(seconds: 0))
        XCTAssertTrue(report.limited); XCTAssertEqual(report.bytesRead, 0)
        XCTAssertEqual(report.stopReason, "Time limit reached")
    }
    func testProgressCanCancelAndRetainsOnlyExactConfirmedGroups() throws {
        let root = try fixture([Data([1]), Data([1]), Data([2,2]), Data([2,2])]); defer { try? FileManager.default.removeItem(at: root) }
        let token = ScanCancellation()
        var observations: [DuplicateReport] = []
        let report = DuplicateFinder.find(root, token: token) { snapshot in
            observations.append(snapshot)
            if !snapshot.groups.isEmpty, snapshot.inProgress { token.cancel() }
        }
        XCTAssertFalse(observations.isEmpty)
        XCTAssertFalse(observations.last!.inProgress)
        XCTAssertFalse(report.groups.isEmpty)
        XCTAssertTrue(report.limited)
        XCTAssertEqual(report.stopReason, "Stopped")
        for group in report.groups { XCTAssertTrue(try DuplicateFinder.sameContents(group.files[0], group.files[1])) }
    }
    func testReplacedPathWithSymlinkIsNotReadAsOriginalFile() throws {
        let root = try fixture([Data([1]), Data([1])]); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("file-0"), other = root.appendingPathComponent("file-1")
        let item = try XCTUnwrap(InventoryService.measure(path))
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: other)
        XCTAssertThrowsError(try DuplicateFinder.digest(item, token: ScanCancellation()))
    }
}
