import XCTest
@testable import Nuke

/// Every rule finds nothing, without failing, on a Mac where its tool or its
/// folders are missing, or its tool fails. After Major Tom's portability test
/// (MIT, (c) 2026 Tom Jordan).
final class EmptyMacTests: XCTestCase {
    func testRulesFindNothingOnAnEmptyMac() throws {
        let empty = URL(fileURLWithPath: "/tmp/nuke-empty-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertTrue(ProjectHibernation.restoreCommands(empty).isEmpty)
        XCTAssertNil(ProjectHibernation.lastActivity(empty.appendingPathComponent("missing"), generated: []))
        XCTAssertTrue(DevCleanups.staleWorktrees(in: empty, token: ScanCancellation()).isEmpty, "not a repository")
        XCTAssertFalse(XcodeLeftovers.projectGone(empty.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-x/Build")))
        XCTAssertFalse(JetBrainsLeftovers.olderVersion(empty.appendingPathComponent("Library/Caches/JetBrains/IDE2024.1")))
        XCTAssertNil(KnownCacheNotes.note(empty.appendingPathComponent("nothing")))
        XCTAssertTrue(AppInventory.leftovers(home: empty, installed: [], reportOnly: true).entries.isEmpty)
        XCTAssertNil(DiskScanner.cache(CacheRule(id: "x", name: "x", relativePath: "missing-\(UUID())", detail: "", symbol: ""), cancellation: ScanCancellation()).item)
        XCTAssertTrue(PersonalFiles.mountedDiskImages().allSatisfy { $0.hasPrefix("/") })
    }

    func testFailingOrSilentToolFallsBackToDefault() throws {
        let folder = URL(fileURLWithPath: "/tmp/nuke-tool-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let failing = folder.appendingPathComponent("brew")
        try "#!/bin/sh\nexit 3\n".write(to: failing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: failing.path)
        let tool = ToolCleaner(id: "test-silent", name: "t", binaries: ["brew"], cache: "Library/Caches/TestTool", arguments: [], effect: "")
        XCTAssertEqual(ToolLocations.cache(for: tool, executable: failing.path).path,
                       DevCleanups.home.appendingPathComponent("Library/Caches/TestTool").path)
    }
}
