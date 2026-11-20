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
