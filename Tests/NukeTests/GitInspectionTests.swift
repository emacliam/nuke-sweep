import XCTest
@testable import Nuke

final class GitInspectionTests: XCTestCase {
    func testTracksFileThroughAliasToRepositorySubfolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-git-alias-" + UUID().uuidString)
        let repo = root.appendingPathComponent("repo")
        let build = repo.appendingPathComponent("build")
        let alias = root.appendingPathComponent("alias")
        let fm = FileManager.default
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        XCTAssertEqual(CommandRunner.run("/usr/bin/git", ["init", repo.path]).status, 0)
        try Data([1]).write(to: build.appendingPathComponent("output.bin"))
        XCTAssertEqual(CommandRunner.run("/usr/bin/git", ["-C", repo.path, "add", "--", "build/output.bin"]).status, 0)
        try fm.createSymbolicLink(at: alias, withDestinationURL: build)
        XCTAssertEqual(GitInspection.inspect(alias.appendingPathComponent("output.bin")), .tracked)
        XCTAssertEqual(GitInspection.inspect(alias), .outsideRepository)
    }

    func testLiteralGlobFilenameIsRecognizedAsTracked() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-git-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(CommandRunner.run("/usr/bin/git", ["init", root.path]).status, 0)
        let tracked = root.appendingPathComponent("build*.bin")
        try Data([1]).write(to: tracked)
        XCTAssertEqual(CommandRunner.run("/usr/bin/git", ["-C", root.path, "add", "--", "build*.bin"]).status, 0)
        // An untracked path that resembles a wildcard must not borrow tracking
        // evidence from a different filename in the same repository.
        let untracked = root.appendingPathComponent("buil*.bin")
        try Data([2]).write(to: untracked)
        XCTAssertEqual(CleanupEvidenceService.gitTracked(tracked), true)
        XCTAssertEqual(CleanupEvidenceService.gitTracked(untracked), false)
    }
}

extension GitInspectionTests {
    func testFailureCategoriesStayUnavailableAndDoNotExposeRawOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-git-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for result in [CommandResult(output:"fatal: dubious ownership /private/sensitive-name", status:128), .init(output:"Permission denied /private/sensitive-name", status:128), .init(output:"xcrun: invalid developer tools",status:1), .init(output:"", status:15)] {
            let inspection = GitInspection.inspect(root) { _, args, timeout in
                XCTAssertEqual(args.first, "--literal-pathspecs"); XCTAssertEqual(timeout, 2); return result
            }
            guard case .unavailable(let reason) = inspection else { XCTFail("Failure must not become untracked"); continue }
            XCTAssertFalse(reason.contains("sensitive-name"))
            XCTAssertThrowsError(try inspection.requireUntracked())
        }
    }
    func testNonRepositoryFileAndDirectoryStopAtFilesystemRoot() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("nuke-git-root-" + UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("output.bin")
        try Data([1]).write(to: file)
        XCTAssertEqual(GitInspection.inspect(root), .outsideRepository)
        XCTAssertEqual(GitInspection.inspect(file), .outsideRepository)
    }
    func testMissingCandidateIsNotAssumedOutsideRepository() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard case .unavailable = GitInspection.inspect(path) else { return XCTFail("Missing item must be unknown") }
    }
    func testDeepRepositoryAncestorRemainsVisible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-git-deep-" + UUID().uuidString)
        let nested = (0..<30).reduce(root) { url, n in url.appendingPathComponent("level-\(n)") }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(CleanupEvidenceService.repoRoot(for: nested)?.path, root.resolvingSymlinksInPath().standardizedFileURL.path)
    }
}
