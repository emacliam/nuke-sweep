import XCTest
@testable import Nuke

final class FeatureTests: XCTestCase {
    func fixture() throws -> URL {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-features-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        return p
    }
    func testGrowthAccountsForAddedAndRemovedFiles() {
        let rows = GrowthComparison.rows(before: ["old": 100, "changed": 10], after: ["new": 50, "changed": 30])
        XCTAssertEqual(rows.first?.name, "old")
        XCTAssertEqual(rows.first?.delta, -100)
        XCTAssertEqual(rows.first(where: { $0.name == "new" })?.delta, 50)
        XCTAssertEqual(rows.first(where: { $0.name == "changed" })?.delta, 20)
    }
    func testCategoryTotalsMatchRegularFileSizes() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 10).write(to: root.appendingPathComponent("a.jpg"))
        try Data(repeating: 0, count: 20).write(to: root.appendingPathComponent("a.pdf"))
        let result = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(result.categories, ["Images": 10, "Documents": 20])
        XCTAssertEqual(result.categories.values.reduce(0, +), result.logical)
    }
    func testDuplicateDetectionExcludesSameSizeDifferentContentsAndHardlinks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
        try Data("same data".utf8).write(to: a); try Data("same data".utf8).write(to: b)
        try Data("different".utf8).write(to: root.appendingPathComponent("other.txt"))
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("hardlink.txt"))
        let report = DuplicateFinder.find(root, token: ScanCancellation())
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].files.count, 2)
        XCTAssertEqual(report.groups[0].extraBytes, 9)
    }
    func testDuplicateRecheckRefusesModifiedCopy() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("same".utf8).write(to: a); try Data("same".utf8).write(to: b)
        let first = InventoryService.measure(a)!, second = InventoryService.measure(b)!
        XCTAssertTrue(try DuplicateFinder.sameContents(first, second))
        try Data("edit".utf8).write(to: b)
        XCTAssertFalse(try DuplicateFinder.sameContents(first, second))
    }
    func testDuplicateCancellationAndSymlinkRoot() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("one"))
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(DuplicateFinder.find(root, token: token).limited)
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertEqual(DuplicateFinder.find(link, token: ScanCancellation()).skipped, 1)
    }
    func testDuplicateCleanupPreflightPreservesKeeper() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("same".utf8).write(to: a); try Data("same".utf8).write(to: b)
        let first = InventoryService.measure(a)!, second = InventoryService.measure(b)!
        let receipt = ReceiptService.moveToTrash([first, second], proofs: [.init(keeper: first, duplicate: second)], runningAppPaths: [])
        XCTAssertTrue(receipt.items.allSatisfy { !$0.success })
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }
    func testProjectDiscoveryGroupsArtifactsWithoutSelectingSource() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: root.appendingPathComponent("node_modules/dependency"))
        try Data("source".utf8).write(to: root.appendingPathComponent("main.ts"))
        let groups = InventoryService.projects(root)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.map { $0.item.name }, ["node_modules"])
        XCTAssertEqual(groups[0].size, 3)
    }
    func testAIInventoryMeasuresKnownToolRootsOnly() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let models = root.appendingPathComponent(".ollama/models")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 20).write(to: models.appendingPathComponent("model"))
        let report = InventoryService.ai(home: root)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].owner, "Ollama")
        XCTAssertEqual(report.entries[0].item.size, 20)
    }
    func testAppRelatedPathsRequireExactIdentifierAndRejectTraversal() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Library/Caches/com.example.app")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let app = InstalledApp(url: root.appendingPathComponent("Missing.app"), name: "Example", bundleID: "com.example.app", version: "1")
        XCTAssertEqual(AppInventory.related(app, home: root).entries.map(\.category), ["Caches"])
        let invalid = InstalledApp(url: app.url, name: app.name, bundleID: "../../outside", version: "1")
        XCTAssertTrue(AppInventory.related(invalid, home: root).entries.isEmpty)
    }
    func testOpenFileParserRetainsPathsWithSpacesAndDeduplicates() {
        let text = "p123\ncTool Name\nn/tmp/a file\nn/tmp/a file\np456\ncOther\nn/tmp/b\n"
        let rows = FileUseService.parse(text)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].path, "/tmp/a file")
        XCTAssertEqual(rows[0].process, "Tool Name")
        XCTAssertEqual(rows[1].pid, 456)
    }
    func testStartupMissingCheckDoesNotInventRelativeExecutableStatus() {
        XCTAssertFalse(StartupService.isMissing("relative-command"))
        XCTAssertFalse(StartupService.isMissing("/bin/sh"))
        XCTAssertTrue(StartupService.isMissing("/tmp/nuke-no-such-command-" + UUID().uuidString))
    }
    func testInventoryDirectoryReportsPermissionGapsButNotMissingRoots() throws {
        let root = try fixture(); defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? FileManager.default.removeItem(at: root) }
        var notes: [String] = []
        XCTAssertTrue(InventoryService.children(root.appendingPathComponent("absent"), notes: &notes).isEmpty)
        XCTAssertTrue(notes.isEmpty)
        guard getuid() != 0 else { throw XCTSkip("Root bypasses mode-based read restrictions") }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        XCTAssertTrue(InventoryService.children(root, notes: &notes).isEmpty)
        XCTAssertTrue(notes.contains { $0.contains("partial") })
    }
    func testEmptyLeftoverScanRetainsScopeNotes() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let report = AppInventory.leftovers(home: root, installed: [])
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertFalse(report.notes.isEmpty)
    }
    func testDeviceInspectionHonorsPreCancelledTraversal() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let token = ScanCancellation(); token.cancel()
        let result = InventoryService.devices(home: root, token: token)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.notes.contains { $0.contains("cancelled") })
    }
    func testCPUDeltasAndReceiptRoundTrip() throws {
        XCTAssertEqual(ResourceMonitor.utilization(before: [10, 10, 70, 10], after: [20, 20, 140, 20]), 30)
        XCTAssertNil(ResourceMonitor.utilization(before: [], after: []))
        let receipt = CleanupReceipt(date: Date(), title: "Test", items: [.init(originalPath: "/tmp/source", trashPath: nil, size: 5, success: false, outcome: "Denied")], freeBefore: 10, freeAfter: 10, undo: "No files moved.")
        let roundtrip = try JSONDecoder().decode(CleanupReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertEqual(roundtrip.items[0].outcome, "Denied")
        XCTAssertFalse(roundtrip.items[0].success)
    }
}
