import XCTest
@testable import Nuke

final class FreshnessTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-fresh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @MainActor func testExternalFolderChangesRefreshVisibleStorageAndStopWhenHidden() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data"); try Data([1]).write(to: file)
        let model = AppModel(restoring: false); model.features.monitor.alertsEnabled = false
        model.page = .storage; model.scanRoot = root
        model.result = DiskScanner.scan(root, cancellation: ScanCancellation())
        model.startStorageUpdates()
        XCTAssertTrue(model.storageIsLive)
        try await Task.sleep(for: .milliseconds(150))
        try Data([1,2,3,4]).write(to: file)
        for _ in 0..<100 where model.result?.logical != 4 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(model.result?.logical, 4)
        model.mainWindowVisible = false; XCTAssertFalse(model.storageIsLive)
        try Data([1,2,3,4,5]).write(to: file)
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(model.result?.logical, 4)
        model.mainWindowVisible = true
        for _ in 0..<100 where model.result?.logical != 5 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(model.result?.logical, 5)
        model.mainWindowVisible = false
    }
    @MainActor func testReceiptRefreshesAfterDeletionEvenWhenMonitoringPaused() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data"); try Data([1,2,3]).write(to: file)
        let model = AppModel(restoring: false); model.features.monitor.alertsEnabled = false; model.features.monitor.monitorPaused = true
        model.page = .storage; model.scanRoot = root; model.result = DiskScanner.scan(root, cancellation: ScanCancellation())
        model.quick.measured = Date(); model.trashUpdated = Date()
        try FileManager.default.removeItem(at: file)
        let receipt = CleanupReceipt(date: Date(), title: "Fixture-only completed removal", items: [.init(originalPath: file.path, trashPath: nil, size: 3, success: true, outcome: "Fixture removed")], freeBefore: nil, freeAfter: nil, undo: "Fixture")
        model.actionBusy = true; model.features.onReceipt?(receipt)
        XCTAssertEqual(model.result?.logical, 3) // wait until the mutation is complete
        model.actionBusy = false
        for _ in 0..<80 where model.result?.logical != 0 || model.features.monitor.sample == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.result?.logical, 0); XCTAssertNotNil(model.features.monitor.sample)
        XCTAssertTrue(model.features.monitor.monitorPaused); XCTAssertNil(model.quick.measured)
        XCTAssertTrue(model.features.receipts.isEmpty) // callback seam never writes fixture receipts to user history
    }
    @MainActor func testInvalidationDiscardsQueuedOldModelInventory() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("weights"))
        let features = FeatureModel(); features.aiCustomPaths = [root.path]
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let held = Task { await DiskWork.run { entered.signal(); release.wait() } }
        // Do not block the main actor waiting for its own Task to start.
        for _ in 0..<40 { if entered.wait(timeout: .now()) == .success { break }; try await Task.sleep(for: .milliseconds(10)) }
        features.scanAI(); try await Task.sleep(for: .milliseconds(40))
        features.invalidateStorageInventories(); release.signal(); await held.value
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(features.ai.entries.isEmpty); XCTAssertFalse(features.aiScanned); XCTAssertFalse(features.aiLoading)
    }
}

extension FreshnessTests {
    @MainActor func testContinuousEventsCannotStarveRefresh() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let freshness = FolderFreshness(); freshness.configure(root)
        var refreshes = 0; freshness.onRefresh = { refreshes += 1 }
        for _ in 0..<30 { freshness.changed(); try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThanOrEqual(refreshes, 1)
        XCTAssertLessThanOrEqual(refreshes, 2) // no refresh for every event
        freshness.stop()
    }
    @MainActor func testDirtyInventoryRefreshesWhenSamePageReopens() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("weights"))
        let model = AppModel(restoring: false); model.features.monitor.alertsEnabled = false
        model.features.aiCustomPaths = [root.path]; model.features.aiScanned = true
        model.page = .ai; model.startStorageUpdates(); model.mainWindowVisible = false
        let receipt = CleanupReceipt(date: Date(), title: "Fixture invalidation", items: [], freeBefore: nil, freeAfter: nil, undo: "Fixture")
        model.features.onReceipt?(receipt)
        XCTAssertFalse(model.features.aiLoading); XCTAssertTrue(model.features.ai.entries.isEmpty)
        model.mainWindowVisible = true
        for _ in 0..<80 where model.features.ai.entries.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.features.ai.entries.first?.item.size, 128)
        model.mainWindowVisible = false
    }
}
