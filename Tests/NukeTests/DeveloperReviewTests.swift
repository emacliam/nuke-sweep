import XCTest
@testable import Nuke

final class DeveloperReviewTests: XCTestCase {
    private func fixture(_ suffix: String) throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/nuke-review-\(suffix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func file(_ relative: String, in root: URL) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url)
    }
    func testDeepNonProjectCacheEntryDoesNotFailAtFourLevels() throws {
        let root = try fixture("deep"); defer { try? FileManager.default.removeItem(at: root) }
        try file("entry/Index.noindex/DataStore/v5/records/AB/CD/blob", in: root)
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("entry")))
        let plan = ReviewPlanner.prepare([item], scopes: [.init(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))], openFiles: { [] })
        XCTAssertTrue(plan.failures.isEmpty, plan.failures.joined(separator: "\n"))
        XCTAssertEqual(plan.items.count, 1)
    }
    func testProjectBeyondFourLevelsIsStillRefused() throws {
        let root = try fixture("source"); defer { try? FileManager.default.removeItem(at: root) }
        try file("entry/a/b/c/d/e/package.json", in: root)
        let item = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("entry")))
        let plan = ReviewPlanner.prepare([item], scopes: [.init(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))], openFiles: { [] })
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.failures.contains { $0.contains("project or source") }, plan.failures.joined(separator: "\n"))
    }

    func testManagedDerivedDataAllowsCopiedPackageSourcesButProtectsNestedGit() throws {
        let root = try fixture("managed"); defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("DerivedData")
        try file("DerivedData/App-hash/SourcePackages/checkouts/pkg/Package.swift", in: root)
        let item = try XCTUnwrap(InventoryService.measure(cache.appendingPathComponent("App-hash")))
        let scopes = [CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))]
        let allowed = ReviewPlanner.prepare([item], scopes: scopes, managedCacheRoots: [cache], openFiles: { [] })
        XCTAssertTrue(allowed.failures.isEmpty, allowed.failures.joined(separator: "\n"))
        XCTAssertEqual(allowed.items.count, 1)
        try file("DerivedData/App-hash/SourcePackages/checkouts/pkg/.git/config", in: root)
        let blocked = ReviewPlanner.prepare([item], scopes: scopes, managedCacheRoots: [cache], openFiles: { [] })
        XCTAssertTrue(blocked.items.isEmpty)
        XCTAssertEqual(blocked.blocked.count, 1)
    }
    func testOneBlockedSelectionDoesNotDiscardVerifiedItems() throws {
        let root = try fixture("mixed"); defer { try? FileManager.default.removeItem(at: root) }
        try file("project/package.json", in: root)
        try file("node_modules/pkg/package.json", in: root)
        let source = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("project")))
        let generated = try XCTUnwrap(InventoryService.measure(root.appendingPathComponent("node_modules")))
        let plan = ReviewPlanner.prepare([source, generated], scopes: [.init(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))], openFiles: { [] })
        XCTAssertEqual(plan.items.map(\.id), [generated.id])
        XCTAssertEqual(plan.blocked.map(\.url), [source.url])
    }
    func testManagedCachePolicyDoesNotTrustAnAliasOutsideTheCache() throws {
        let root = try fixture("alias"); defer { try? FileManager.default.removeItem(at: root) }
        try file("cache/data", in: root); try file("source/package.json", in: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cache/alias"), withDestinationURL: root.appendingPathComponent("source"))
        XCTAssertFalse(ReviewPlanner.isManagedCache(root.appendingPathComponent("cache/alias"), roots: [root.appendingPathComponent("cache")]))
    }
    func testDerivedDataContentReviewKeepsContainersAndSeparatesProtectedCheckouts() throws {
        let root = try fixture("xcode-contents"); defer { try? FileManager.default.removeItem(at: root) }
        try file("DerivedData/App-hash/Build/Products/app.o", in: root)
        try file("DerivedData/App-hash/SourcePackages/pkg/.git/config", in: root)
        let cache = root.appendingPathComponent("DerivedData")
        let contents = ReviewPlanner.cacheCandidates(at: cache, xcodeContainers: true, token: ScanCancellation())
        XCTAssertEqual(Set(contents.items.map(\.name)), Set(["Build", "SourcePackages"]))
        let plan = ReviewPlanner.prepare(contents.items, scopes: [.init(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))], managedCacheRoots: [cache], openFiles: { [] })
        XCTAssertEqual(plan.items.map(\.name), ["Build"])
        XCTAssertEqual(plan.blocked.map { $0.url.lastPathComponent }, ["SourcePackages"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.appendingPathComponent("App-hash").path))
    }

}
