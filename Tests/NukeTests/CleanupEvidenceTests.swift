import XCTest
@testable import Nuke

final class CleanupEvidenceTests: XCTestCase {
    func testKnownCacheDependencyAndSensitiveLabels() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(CleanupEvidenceService.classify(home.appendingPathComponent("Library/Caches/pip")).kind, .knownCache)
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/node_modules")).kind, .dependency)
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/.git")).kind, .sensitive)
        XCTAssertTrue(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/.git")).kind.isBlocked)
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/build")).kind, .buildOutput)
    }

    func testCopiedManifestInBuildOutputAndSourceLikeFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-evidence-" + UUID().uuidString)
        let dist = root.appendingPathComponent("dist"), src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: dist.appendingPathComponent("package.json"))
        try Data([1]).write(to: src.appendingPathComponent("main.swift"))

        XCTAssertEqual(CleanupEvidenceService.classify(dist).kind, .buildOutput)
        XCTAssertEqual(CleanupEvidenceService.classify(src, sourceCheck: true).kind, .sourceLike)
        XCTAssertEqual(CleanupEvidenceService.classify(src, sourceCheck: false).kind, .unknown)
    }

    func testUnknownAndGitIgnoredEvidence() {
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/notes.txt")).kind, .unknown)
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/notes.txt"), gitIgnored: true).kind, .gitIgnored)
        XCTAssertEqual(CleanupEvidenceService.classify(URL(fileURLWithPath: "/tmp/project/notes.txt"), gitIgnored: false).kind, .unknown)
    }
}
