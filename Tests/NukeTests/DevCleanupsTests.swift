import XCTest
@testable import Nuke

final class DevCleanupsTests: XCTestCase {
    func testEveryToolCommandIsItsOwnCleaner() {
        for tool in ToolCleaner.all {
            XCTAssertFalse(tool.arguments.isEmpty, tool.id)
            XCTAssertFalse(tool.arguments.contains { $0.contains("rm -rf") || $0 == "-rf" }, tool.id)
            XCTAssertFalse(tool.cache.hasPrefix("/"), "cache is relative to home: \(tool.id)")
        }
        XCTAssertEqual(Set(ToolCleaner.all.map(\.id)).count, ToolCleaner.all.count)
    }

    func testCleanMergedWorktreeIsOfferedAndDirtyOneIsNot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ args: String...) { _ = CommandRunner.run("/usr/bin/git", ["-C", repo.path] + args, timeout: 20) }
        git("init", "-q", "-b", "main")
        git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        git("worktree", "add", "-q", "-b", "merged", root.appendingPathComponent("merged").path)
        git("worktree", "add", "-q", "-b", "dirty", root.appendingPathComponent("dirty").path)
        try "x".write(to: root.appendingPathComponent("dirty/new.txt"), atomically: true, encoding: .utf8)
        let found = DevCleanups.staleWorktrees(in: repo, token: ScanCancellation())
        XCTAssertEqual(found.map(\.branch), ["merged"])
    }
}
