import Foundation
import XCTest
@testable import Nuke

final class DeveloperScopeEnforcementTests: XCTestCase {
    func testReviewAndExecutionRespectNewExclusionsAcrossEntryPoints() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/scope-policy-" + UUID().uuidString)
        let build = root.appendingPathComponent("build")
        let fm = FileManager.default
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data([1]).write(to: build.appendingPathComponent("output.bin"))
        let item = try XCTUnwrap(InventoryService.measure(build))
        let reviewed = try XCTUnwrap(ReviewPlanner.prepare([item], scopes: [], openFiles: { [] }).items.first)
        let changedScope = DeveloperScope(label: "Fixture", path: root.path, cleanupAllowed: true,
                                          exclusions: ["BUILD/output.bin"])

        let preparation = ReviewPlanner.prepare([item], scopes: [], developerScopes: [changedScope], openFiles: { [] })
        XCTAssertTrue(preparation.items.isEmpty)
        XCTAssertTrue(preparation.failures.contains { $0.contains("excluded path") })

        let receipt = ReceiptService.moveToTrash([reviewed], proofs: [], runningAppPaths: [],
                                                 developerScopes: [changedScope]) { _ in
            XCTFail("A new exclusion must prevent the move")
            return nil
        }
        XCTAssertFalse(try XCTUnwrap(receipt.items.first).success)
        XCTAssertTrue(fm.fileExists(atPath: build.path))
    }

    func testResolvedAliasCannotBypassInspectOnlyScope() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/scope-alias-" + UUID().uuidString)
        let project = root.appendingPathComponent("project")
        let alias = root.appendingPathComponent("alias")
        let fm = FileManager.default
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data([1]).write(to: project.appendingPathComponent("output.bin"))
        try fm.createSymbolicLink(at: alias, withDestinationURL: project)
        let item = try XCTUnwrap(InventoryService.measure(alias.appendingPathComponent("output.bin")))
        let scope = DeveloperScope(label: "Fixture", path: project.path)
        XCTAssertThrowsError(try CleanupSafety.validate(item, developerScopes: [scope])) { error in
            XCTAssertTrue(error.localizedDescription.contains("inspection only"))
        }
    }
}
