import XCTest
@testable import Nuke

final class ProjectHibernationTests: XCTestCase {
    func testRestoreCommandsComeFromLockfiles() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-proj-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ios"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["package.json", "pnpm-lock.yaml", "ios/Podfile"] { try Data().write(to: root.appendingPathComponent(name)) }
        XCTAssertEqual(ProjectHibernation.restoreCommands(root), ["pnpm install", "cd ios && pod install"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("pnpm-lock.yaml"))
        try Data().write(to: root.appendingPathComponent("yarn.lock"))
        XCTAssertEqual(ProjectHibernation.restoreCommands(root).first, "yarn install")
    }

    func testActivityIgnoresGeneratedFolders() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-proj-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("index.js")
        try Data().write(to: source)
        let old = Date(timeIntervalSinceNow: -200 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source.path)
        let activity = try XCTUnwrap(ProjectHibernation.lastActivity(root, generated: ["node_modules"]))
        XCTAssertLessThan(activity, Date(timeIntervalSinceNow: -100 * 86_400), "a fresh node_modules does not make the project active")
    }
}

final class ProjectGitWarningTests: XCTestCase {
    func testWarnsAboutUncommittedWorkAndNoRemote() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-gitwarn-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: String...) { _ = CommandRunner.run("/usr/bin/git", ["-C", root.path] + args, timeout: 20) }
        git("init", "-q", "-b", "main")
        git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        try Data("x".utf8).write(to: root.appendingPathComponent("work.txt"))
        let warnings = ProjectHibernation.gitWarnings(root)
        XCTAssertTrue(warnings.contains("uncommitted changes"), warnings.joined())
        XCTAssertTrue(warnings.contains { $0.hasPrefix("no remote") }, warnings.joined())
    }
}
