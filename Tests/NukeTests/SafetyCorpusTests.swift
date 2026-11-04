import XCTest
@testable import Nuke

final class SafetyCorpusTests: XCTestCase {
    private func root(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/nuke-corpus-\(name)-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scope(_ root: URL) throws -> CleanupScope {
        CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
    }

    private func prepare(_ folder: URL, root: URL) throws -> ReviewPreparation {
        let item = try XCTUnwrap(InventoryService.measure(folder))
        return ReviewPlanner.prepare([item], scopes: [try scope(root)])
    }

    func testCommonProjectRootsAreRefused() throws {
        let cases: [(String, [String], String)] = [
            ("xcode", ["App.xcodeproj/project.pbxproj", "App/main.swift"], "App.xcodeproj"),
            ("node", ["package.json", "src/index.js"], "src"),
            ("python", ["pyproject.toml", "app/main.py"], "app"),
            ("rust", ["Cargo.toml", "src/main.rs"], "src"),
            ("go", ["go.mod", "main.go"], "")
        ]
        for (name, files, folderName) in cases {
            let base = try root(name); defer { try? FileManager.default.removeItem(at: base) }
            for file in files {
                let url = base.appendingPathComponent(file)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([1]).write(to: url)
            }
            let target = folderName.isEmpty ? base : base.appendingPathComponent(folderName)
            let plan = try prepare(target, root: base)
            XCTAssertTrue(plan.items.isEmpty, "\(name) should be refused")
            XCTAssertFalse(plan.failures.isEmpty, "\(name) should explain the refusal")
        }
    }

    func testNestedMonorepoMetadataIsRefusedAtTheContainer() throws {
        let base = try root("monorepo"); defer { try? FileManager.default.removeItem(at: base) }
        let container = base.appendingPathComponent("code")
        let manifest = container.appendingPathComponent("packages/web/package.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: manifest)
        let plan = try prepare(container, root: base)
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.failures.contains { $0.contains("project or source folder") })
    }

    func testUntrackedDistWithManifestIsAllowed() throws {
        let base = try root("dist"); defer { try? FileManager.default.removeItem(at: base) }
        let dist = base.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dist.appendingPathComponent("package.json"))
        let plan = try prepare(dist, root: base)
        XCTAssertTrue(plan.failures.isEmpty)
        XCTAssertEqual(plan.items.count, 1)
    }

    func testGitTrackedDistIsRefusedButIgnoredDistIsNot() throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/git") else { throw XCTSkip("git unavailable") }
        let base = try root("git"); defer { try? FileManager.default.removeItem(at: base) }
        _ = CommandRunner.run("/usr/bin/git", ["-C", base.path, "init", "-q"], timeout: 5)
        let tracked = base.appendingPathComponent("committed-dist")
        try FileManager.default.createDirectory(at: tracked, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tracked.appendingPathComponent("package.json"))
        _ = CommandRunner.run("/usr/bin/git", ["-C", base.path, "add", "committed-dist/package.json"], timeout: 5)
        let refused = try prepare(tracked, root: base)
        XCTAssertTrue(refused.items.isEmpty)
        XCTAssertTrue(refused.failures.contains { $0.contains("tracked by git") })

        try Data("ignored-dist/\n".utf8).write(to: base.appendingPathComponent(".gitignore"))
        let ignored = base.appendingPathComponent("ignored-dist")
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ignored.appendingPathComponent("package.json"))
        let allowed = try prepare(ignored, root: base)
        XCTAssertTrue(allowed.failures.isEmpty)
    }
}
