import XCTest
@testable import Nuke

final class PolishTests: XCTestCase {
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-polish-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func testCustomModelFolderAndCancelledInspection() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: custom.appendingPathComponent("weights"))
        let report = InventoryService.ai(home: home, custom: [custom, custom])
        XCTAssertEqual(report.entries.count, 1); XCTAssertEqual(report.entries[0].item.size, 128)
        XCTAssertFalse(report.entries[0].removable); XCTAssertTrue(report.entries[0].explanation.contains("User-selected"))
        let token = ScanCancellation(); token.cancel()
        let cancelled = InventoryService.ai(home: home, custom: [custom], token: token)
        XCTAssertTrue(cancelled.entries.isEmpty); XCTAssertTrue(cancelled.notes.contains { $0.contains("stopped") })
        XCTAssertTrue(AppInventory.apps(roots: [home], token: token).isEmpty)
        XCTAssertTrue(InventoryService.projects(home, token: token).isEmpty)
        XCTAssertThrowsError(try TrashService(root: home).inspect(token: token))
    }
    func testOllamaMetadataSkipsSymlinksAndDoesNotOfferBlobDeletion() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".ollama/models"), manifests = root.appendingPathComponent("manifests/registry/library/example")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data(#"{"layers":[{"digest":"sha256:shared","size":123}]}"#.utf8).write(to: manifests.appendingPathComponent("latest"))
        try FileManager.default.createSymbolicLink(at: manifests.appendingPathComponent("alias"), withDestinationURL: manifests.appendingPathComponent("latest"))
        let report = InventoryService.ai(home: home)
        let records = LocalModelCatalog.inspect(report.entries, token: ScanCancellation())
        XCTAssertEqual(records.count, 1); XCTAssertTrue(records[0].name.hasSuffix("example/latest")); XCTAssertTrue(records[0].detail.contains("shared"))
        XCTAssertEqual(report.entries.count, 1) // only the reviewed root, never individual shared layers
    }
    func testOversizedManifestIsNotLoadedAsModelMetadata() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let manifests = home.appendingPathComponent(".ollama/models/manifests")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        try Data(repeating: 32, count: 70_000).write(to: manifests.appendingPathComponent("huge"))
        XCTAssertTrue(LocalModelCatalog.inspect(InventoryService.ai(home: home).entries, token: ScanCancellation()).isEmpty)
    }
    func testHubMetadataRecognizesRepositoriesOnly() throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let hub = home.appendingPathComponent(".cache/huggingface/hub")
        for name in ["models--team--model", "datasets--team--data", ".locks"] { try FileManager.default.createDirectory(at: hub.appendingPathComponent(name), withIntermediateDirectories: true) }
        let records = LocalModelCatalog.inspect(InventoryService.ai(home: home).entries, token: ScanCancellation())
        XCTAssertEqual(records.map(\.name), ["team/model"])
    }
    func testForegroundDiskJobRunsBeforePendingWatch() async throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let order = JobOrder()
        let first = Task { await DiskWork.run("held") { entered.signal(); release.wait() } }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let watch = Task { await DiskWork.run("watch", priority: .background) { order.append("watch") } }
        try await Task.sleep(for: .milliseconds(60))
        let user = Task { await DiskWork.run("user") { order.append("user") } }
        try await Task.sleep(for: .milliseconds(60)); release.signal()
        await first.value; await watch.value; await user.value
        XCTAssertEqual(order.values, ["user", "watch"])
    }
}
private final class JobOrder: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func append(_ value: String) { lock.lock(); items.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
