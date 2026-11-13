import XCTest
@testable import Nuke

final class DeveloperScopeTests: XCTestCase {
    func testExclusionNormalizationKeepsRelativeRulesAndDropsEscapes() {
        let root = URL(fileURLWithPath: "/tmp/nuke-scope")
        let rules = DeveloperScope.normalizeExclusions(" node_modules, build/ , ./dist\n/tmp/nuke-scope/src/generated; ../escape; node_modules", root: root)
        XCTAssertEqual(rules, ["node_modules", "build", "dist", "src/generated"])
    }

    func testExcludedPathsAndAncestorSelection() {
        let scope = DeveloperScope(label: "Test", path: "/tmp/nuke-scope", cleanupAllowed: false, exclusions: ["app/node_modules", "build"])
        XCTAssertTrue(scope.isExcluded(URL(fileURLWithPath: "/tmp/nuke-scope/app/node_modules/pkg")))
        XCTAssertTrue(scope.isExcluded(URL(fileURLWithPath: "/tmp/nuke-scope/build/out")))
        XCTAssertFalse(scope.isExcluded(URL(fileURLWithPath: "/tmp/nuke-scope/src/main.swift")))

        XCTAssertTrue(blocks(scope, URL(fileURLWithPath: "/tmp/nuke-scope/app/node_modules/pkg")))
        XCTAssertTrue(blocks(scope, URL(fileURLWithPath: "/tmp/nuke-scope/app")))
        XCTAssertFalse(blocks(scope, URL(fileURLWithPath: "/tmp/nuke-scope/src")))
        XCTAssertTrue(blocks(scope, URL(fileURLWithPath: "/tmp/nuke-scope")))
    }

    func testScannerSkipsExcludedFilesAndDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-scope-" + UUID().uuidString)
        let keepDir = root.appendingPathComponent("keepdir"), skipDir = root.appendingPathComponent("skipdir")
        try FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skipDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 64).write(to: root.appendingPathComponent("keep.txt"))
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("skip.txt"))
        try Data(repeating: 1, count: 256).write(to: skipDir.appendingPathComponent("inside.txt"))
        try Data(repeating: 1, count: 512).write(to: keepDir.appendingPathComponent("inside.txt"))

        let scope = DeveloperScope(label: "Fixture", path: root.path, cleanupAllowed: false, exclusions: ["skip.txt", "skipdir"])
        let result = DiskScanner.scan(root, cancellation: ScanCancellation(), excluding: scope.isExcluded)

        XCTAssertEqual(Set(result.items.map(\.name)), ["keep.txt", "keepdir"])
        XCTAssertEqual(result.logical, 576)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertFalse(result.limited)
        XCTAssertFalse(scope.blocksSelection(DiskItem(url: keepDir, size: 512, allocated: 512, directory: true, symlink: false, modified: nil, identity: nil, incomplete: false)))
    }

    func testScopeRoundTripsThroughJSON() throws {
        let scope = DeveloperScope(label: "Demo", path: "/tmp/demo", cleanupAllowed: true, exclusions: ["build", "node_modules"])
        let restored = try JSONDecoder().decode(DeveloperScope.self, from: JSONEncoder().encode(scope))
        XCTAssertEqual(restored, scope)
    }

    func testPresetsAreSafeRelativeStartingPoints() {
        let ids = DeveloperScopePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ["deno", "flutter", "jvm", "dotnet"] { XCTAssertTrue(ids.contains(id), id) }
        for preset in DeveloperScopePreset.all {
            XCTAssertFalse(preset.exclusions.isEmpty)
            XCTAssertTrue(preset.scope.cleanupAllowed)
            XCTAssertTrue(preset.exclusions.allSatisfy { !$0.hasPrefix("/") && !$0.contains("..") && !$0.contains("*") })
        }
    }

    private func blocks(_ scope: DeveloperScope, _ url: URL) -> Bool {
        scope.blocksSelection(DiskItem(url: url, size: 0, allocated: 0, directory: true, symlink: false, modified: nil, identity: nil, incomplete: false))
    }
}

final class PlanScopeTests: XCTestCase {
    func testApplyingExclusionsUsesRelativePathsAndDeduplicates() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-plan-scope-\(UUID().uuidString)")
        let existing = DeveloperScope(label: "Example", path: root.path, cleanupAllowed: false, exclusions: ["src"])
        let additions = [
            root.appendingPathComponent("src"),
            root.appendingPathComponent("node_modules"),
            URL(fileURLWithPath: "/tmp/outside-project/cache")
        ]
        let scope = DeveloperScope.applyingPlanExclusions(root: root, existing: existing, additions: additions)
        XCTAssertEqual(scope.exclusions, ["src", "node_modules"])
        XCTAssertFalse(scope.cleanupAllowed)
        XCTAssertEqual(scope.id, existing.id)
    }

    func testApplyingExclusionsCreatesAScopeWhenMissing() {
        let root = URL(fileURLWithPath: "/tmp/nuke-plan-new-\(UUID().uuidString)")
        let scope = DeveloperScope.applyingPlanExclusions(root: root, existing: nil, additions: [root.appendingPathComponent("dist")])
        XCTAssertEqual(scope.path, root.standardizedFileURL.path)
        XCTAssertEqual(scope.exclusions, ["dist"])
        XCTAssertTrue(scope.cleanupAllowed)
        XCTAssertEqual(scope.label, root.lastPathComponent)
    }
}
