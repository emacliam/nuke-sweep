import XCTest
@testable import Nuke

@MainActor
final class ScheduledExecutionTests: XCTestCase {
    func testRunNowScansARealFolderAndUpdatesSchedule() async throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-scheduled-run-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 256).write(to: root.appendingPathComponent("sample.bin"))

        let suite = "nuke.tests.scheduled-run." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ScheduledScanStore(defaults: defaults)
        var scannedURL: URL?
        var scannedBytes: Int64?
        store.onScan = { url, result in scannedURL = url; scannedBytes = result.logical; return nil }
        let id = store.add(root, frequency: .daily)
        store.runNow(id)

        let deadline = Date().addingTimeInterval(6)
        while (store.runningID != nil || scannedBytes == nil) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(scannedURL?.standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertEqual(scannedBytes, 256)
        XCTAssertNotNil(store.scans.first?.lastRun)
        XCTAssertTrue(store.scans.first?.lastResult?.contains("1 items") == true)
        XCTAssertNil(store.runningID)
    }
}
