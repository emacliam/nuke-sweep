import XCTest
@testable import Nuke

final class SeamlessTests: XCTestCase {
    func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/nuke-repeat-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        return root
    }
    func testIncrementalScanReusesUnchangedBranchesAndFullScanDoesNot() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 1024).write(to: root.appendingPathComponent("nested/data"))
        let scanner = IncrementalScanner()
        let first = scanner.scan(root, token: ScanCancellation())
        XCTAssertEqual(first.result.logical, 1024); XCTAssertEqual(first.reused, 0)
        var reused = scanner.scan(root, token: ScanCancellation())
        for _ in 0..<5 where reused.reused == 0 { Thread.sleep(forTimeInterval: 0.25); reused = scanner.scan(root, token: ScanCancellation()) }
        XCTAssertGreaterThan(reused.reused, 0)
        XCTAssertEqual(reused.result.logical, 1024)
        XCTAssertEqual(scanner.scan(root, token: ScanCancellation(), force: true).reused, 0)
    }
    func testNestedFileChangeInvalidatesBranch() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/data")
        try Data(repeating: 1, count: 1024).write(to: file)
        let scanner = IncrementalScanner(); _ = scanner.scan(root, token: ScanCancellation())
        Thread.sleep(forTimeInterval: 0.5)
        try Data(repeating: 1, count: 3072).write(to: file)
        var result = scanner.scan(root, token: ScanCancellation())
        for _ in 0..<8 where result.result.logical != 3072 { Thread.sleep(forTimeInterval: 0.25); result = scanner.scan(root, token: ScanCancellation()) }
        XCTAssertEqual(result.result.logical, 3072)
        scanner.invalidate(); XCTAssertEqual(scanner.scan(root, token: ScanCancellation()).reused, 0)
    }
    func testDeadlineAndCancellationPreventUnboundedTraversal() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("nested/data"))
        XCTAssertTrue(DiskScanner.scan(root, cancellation: ScanCancellation(), deadline: .distantPast).limited)
        let token = ScanCancellation(); token.cancel()
        let result = IncrementalScanner().scan(root, token: token)
        XCTAssertTrue(result.result.limited); XCTAssertEqual(result.result.visited, 0)
    }
    func testUnitsAndWorkspaceRoundTrip() throws {
        XCTAssertEqual(ChartByteScale(maximum: 4e6).unit, "MB")
        XCTAssertEqual(ChartByteScale(maximum: 4e9).unit, "GB")
        let state = WorkspaceState(page: Page.storage.rawValue, root: URL(fileURLWithPath: "/tmp/example"), filters: [Page.storage.rawValue: "models"], focusedItem: "chosen", snapshot: nil, measured: nil)
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.filters[Page.storage.rawValue], "models"); XCTAssertEqual(loaded.focusedItem, "chosen")
    }
    @MainActor func testGrowthThresholdAvoidsNoise() {
        XCTAssertFalse(AlertCenter.significantGrowth(before: 1_000_000_000, after: 1_001_000_000))
        XCTAssertTrue(AlertCenter.significantGrowth(before: 100_000_000, after: 300_000_000))
        XCTAssertTrue(AlertCenter.significantGrowth(before: 10_000_000_000, after: 11_000_000_000))
    }
    func testReviewPlanDropsNestedSelectionsAndRefreshesSize() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("nested")))
        let fileURL = root.appendingPathComponent("nested/data"); try Data([1,2,3]).write(to: fileURL)
        let file = try XCTUnwrap(InventoryService.measure(fileURL))
        XCTAssertEqual(ReviewPlanner.topLevel([folder, file]).count, 1)
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let prepared = ReviewPlanner.prepare([folder, file], scopes: [scope])
        XCTAssertTrue(prepared.failures.isEmpty); XCTAssertEqual(prepared.items.first?.size, 3)
    }
    func testReviewRefusesAProjectRootButAllowsABuildFolder() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project"), build = project.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        let projectItem = try XCTUnwrap(InventoryService.measure(project))
        let buildItem = try XCTUnwrap(InventoryService.measure(build))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))

        let refused = ReviewPlanner.prepare([projectItem], scopes: [scope])
        XCTAssertTrue(refused.items.isEmpty)
        XCTAssertTrue(refused.failures.contains { $0.contains("project or source folder") })

        let allowed = ReviewPlanner.prepare([buildItem], scopes: [scope])
        XCTAssertTrue(allowed.failures.isEmpty)
        XCTAssertEqual(allowed.items.count, 1)
    }
    func testProjectRootDetectionCoversCommonManifests() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(ReviewPlanner.looksLikeProjectRoot(root))
        try Data("{}".utf8).write(to: root.appendingPathComponent("Cargo.toml"))
        XCTAssertTrue(ReviewPlanner.looksLikeProjectRoot(root))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        XCTAssertTrue(ReviewPlanner.looksLikeProjectRoot(root))
    }
    func testReviewRefusesAContainerWithNestedProjectMetadata() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("code"), project = container.appendingPathComponent("myapp")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let item = try XCTUnwrap(InventoryService.measure(container))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope])
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.failures.contains { $0.contains("project or source folder") })
    }

    func testReviewAllowsACopiedManifestInBuildOutput() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let dist = root.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dist.appendingPathComponent("package.json"))
        let item = try XCTUnwrap(InventoryService.measure(dist))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope])
        XCTAssertTrue(plan.failures.isEmpty)
        XCTAssertEqual(plan.items.count, 1)
    }

    func testReviewRefusesSourceLikeFolderWithoutMarkers() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data([1]).write(to: src.appendingPathComponent("main.swift"))
        let item = try XCTUnwrap(InventoryService.measure(src))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope])
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.failures.contains { $0.contains("source-like") })
    }

    func testReviewAllowsADependencyFolderWithNestedManifests() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let modules = root.appendingPathComponent("node_modules"), package = modules.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: package.appendingPathComponent("package.json"))
        let item = try XCTUnwrap(InventoryService.measure(modules))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope])
        XCTAssertTrue(plan.failures.isEmpty)
        XCTAssertEqual(plan.items.count, 1)
    }


    func testSensitivePathsAreClassified() {
        let home = "/Users/tester"
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/.ssh/id_ed25519", home: home))
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/code/app/.git", home: home))
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/Library/Keychains", home: home))
        XCTAssertTrue(CleanupSafety.isSensitive(home + "/Library/Messages/chat.db", home: home))
        XCTAssertFalse(CleanupSafety.isSensitive(home + "/code/app/build", home: home))
        XCTAssertFalse(CleanupSafety.isSensitive(home + "/Library/Caches/pip", home: home))
    }

    func testReviewRefusesGitMetadataDirectly() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let git = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let item = try XCTUnwrap(InventoryService.measure(git))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope])
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.failures.contains { $0.contains("source-control metadata") })
    }

    func testDiskWorkSerializesConcurrentRequests() async {
        let counter = WorkCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await DiskWork.run { counter.enter(); Thread.sleep(forTimeInterval: 0.005); counter.leave() } } }
        }
        XCTAssertEqual(counter.maximum, 1)
    }
}
private final class WorkCounter: @unchecked Sendable {
    private let lock = NSLock(); private var active = 0
    private(set) var maximum = 0
    func enter() { lock.lock(); active += 1; maximum = max(active, maximum); lock.unlock() }
    func leave() { lock.lock(); active -= 1; lock.unlock() }
}

extension SeamlessTests {
    func testCancelledReviewNeverReturnsAPlan() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("nested")))
        let token = ScanCancellation(); token.cancel()
        let scopes = [CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))]
        let plan = ReviewPlanner.prepare([item], scopes: scopes, token: token)
        XCTAssertTrue(plan.items.isEmpty); XCTAssertFalse(plan.failures.isEmpty)
    }
    func testSavedDockerRowsRemainCodableWithoutClaimingReachability() throws {
        let saved = DockerSavedUsage(context: "remote", rows: [.init(type: "Images", total: "3", active: "1", size: "3GB", reclaimable: "1GB")], date: Date())
        let decoded = try JSONDecoder().decode(DockerSavedUsage.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.context, "remote"); XCTAssertEqual(decoded.rows[0].total, "3")
    }
}

extension SeamlessTests {
}

extension SeamlessTests {
    func testAlertReviewNeverFallsBackToAnUnrelatedFolder() {
        let root = URL(fileURLWithPath: "/tmp/watched-project")
        let alert = NukeAlert(id: UUID(), key: "growth:fixture", date: Date(), title: "Grew", detail: "Fixture", root: root)
        XCTAssertEqual(AlertCenter.route(alert, scanRoots: ["/tmp/other-project"]), .storage(root))
        XCTAssertEqual(AlertCenter.route(alert, scanRoots: [root.path]), .growth(root.path))
    }
    func testCachedScanAvoidsDeepTraversalWork() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for branch in 0..<10 {
            let directory = root.appendingPathComponent("branch-\(branch)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in 0..<100 { try Data(repeating: 1, count: 128).write(to: directory.appendingPathComponent("\(file)")) }
        }
        let scanner = IncrementalScanner(), start = Date()
        let first = scanner.scan(root, token: ScanCancellation(), force: true)
        let fullTime = Date().timeIntervalSince(start)
        var cached = scanner.scan(root, token: ScanCancellation())
        for _ in 0..<5 where cached.reused == 0 { Thread.sleep(forTimeInterval: 0.25); cached = scanner.scan(root, token: ScanCancellation()) }
        let cachedStart = Date(); cached = scanner.scan(root, token: ScanCancellation())
        let cachedTime = Date().timeIntervalSince(cachedStart)
        XCTAssertEqual(cached.result.logical, first.result.logical)
        XCTAssertGreaterThan(first.result.visited, 1000); XCTAssertLessThan(cached.result.visited, first.result.visited / 2)
        print("NUKE_SCAN_BENCH full_seconds=\(fullTime) cached_seconds=\(cachedTime) full_entries=\(first.result.visited) cached_entries=\(cached.result.visited) reused=\(cached.reused)")
    }
}

extension SeamlessTests {
    func testShutdownStopsOnlyNukeOwnedCommandChildren() async {
        let start = Date()
        let running = Task.detached { CommandRunner.run("/bin/sleep", ["10"], timeout: 15) }
        try? await Task.sleep(for: .milliseconds(100))
        CommandRunner.shutdown()
        let result = await running.value
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}

extension SeamlessTests {
    @MainActor func testQuickPassReachesFinishedState() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1,2,3]).write(to: root.appendingPathComponent("nested/data"))
        let model = AppModel(restoring: false)
        model.findSpace(rootsOverride: [("Application caches", root)], includeTrash: false)
        for _ in 0..<80 where model.quick.busy { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(model.quick.busy)
        XCTAssertNotNil(model.quick.measured)
        XCTAssertEqual(model.quick.entries.first?.item.size, 3)
    }
}
