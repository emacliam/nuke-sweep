import XCTest
@testable import Nuke

final class StreamingTests: XCTestCase {
    func testDirectoryVisitStopsBeforeReadingRemainingEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<1000 { try Data([1]).write(to: root.appendingPathComponent("item-\(index)")) }
        var seen = 0
        let complete = try DirectoryEntries.visit(root, shouldContinue: { seen < 3 }) { _ in seen += 1 }
        XCTAssertFalse(complete)
        XCTAssertEqual(seen, 3)
        let result = DiskScanner.scan(root, cancellation: ScanCancellation(), limit: 1001)
        XCTAssertEqual(result.items.count, 1000)
        XCTAssertEqual(result.logical, 1000)
        XCTAssertFalse(result.limited)
    }
    func testSharedStopCancelsActiveInspection() async {
        let entered = expectation(description: "active inspection")
        let token = ScanCancellation()
        let task = Task {
            await DiskWork.run("Cancellation fixture", cancellation: token) {
                entered.fulfill()
                let deadline = Date().addingTimeInterval(2)
                while !token.cancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
                return token.cancelled
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        DiskWork.cancelActiveInspection()
        let stopped = await task.value
        XCTAssertTrue(stopped)
    }
}

extension StreamingTests {
    func testStreamRefusesSymlinkDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try DirectoryEntries.visit(link, shouldContinue: { true }) { _ in XCTFail("Must not follow the directory link") })
    }
    @MainActor func testCacheStopPersistsAnExplicitOutcome() async throws {
        let model = AppModel(restoring: false)
        model.scanCaches(); model.cancelCaches()
        for _ in 0..<80 where model.cacheScanning { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(model.cacheScanning)
        XCTAssertEqual(model.cacheOutcome, "Stopped — partial results")
        XCTAssertLessThan(model.caches.count, CacheRule.all.count)
    }
    @MainActor func testFolderStopIsNotReportedAsBudgetExhaustion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(restoring: false)
        model.scan(root, force: true); model.cancelScan()
        for _ in 0..<80 where model.scanning { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(model.scanState, "Stopped — partial results")
        XCTAssertEqual(model.result?.limited, true)
    }
}
