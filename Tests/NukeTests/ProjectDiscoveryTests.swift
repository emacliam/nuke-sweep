import XCTest
@testable import Nuke

final class ProjectDiscoveryTests: XCTestCase {
    func testFindsNestedWorkspacesAndRanksDependenciesWithoutTraversingThem() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-projects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, count) in [("work/team/large/node_modules/pkg/node_modules/file", 4096), ("work/small/node_modules/file", 128)] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: count).write(to: file)
        }
        let report = ProjectDiscovery.scan(root, token: ScanCancellation())
        XCTAssertFalse(report.limited)
        XCTAssertEqual(report.projects.count, 2)
        XCTAssertEqual(report.projects.first?.root.lastPathComponent, "large")
        XCTAssertEqual(report.projects.flatMap(\.entries).count, 2)
        XCTAssertEqual(report.projects.first?.size, 4096)
        let stopped = ScanCancellation(); stopped.cancel()
        XCTAssertTrue(ProjectDiscovery.scan(root, token: stopped).limited)
        XCTAssertTrue(ProjectDiscovery.scan(root, token: ScanCancellation(), maxDepth: 0).limited)
        XCTAssertTrue(ProjectDiscovery.scan(root, token: ScanCancellation(), maxDirectories: 1).limited)
    }
}

final class ProjectKindTests: XCTestCase {
    func testDetectsDenoFlutterJVMAndDotNetWorkspaces() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-project-kinds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures: [(String, String, String)] = [
            ("deno-app", "deno.json", "dist"),
            ("flutter-app", "pubspec.yaml", ".dart_tool"),
            ("jvm-app", "build.gradle", "build"),
            ("dotnet-app", "App.csproj", "bin")
        ]
        for (name, marker, artifact) in fixtures {
            let project = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: project.appendingPathComponent(marker))
            let artifactURL = project.appendingPathComponent(artifact)
            try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: artifactURL.appendingPathComponent("output"))
        }
        let report = ProjectDiscovery.scan(root, token: ScanCancellation())
        let kinds = Dictionary(uniqueKeysWithValues: report.projects.map { ($0.root.lastPathComponent, $0.kind) })
        XCTAssertEqual(kinds["deno-app"], "Deno / TypeScript")
        XCTAssertEqual(kinds["flutter-app"], "Flutter / Dart")
        XCTAssertEqual(kinds["jvm-app"], "Java / Kotlin")
        XCTAssertEqual(kinds["dotnet-app"], ".NET")
    }
}

final class ProjectRebuildGuidanceTests: XCTestCase {
    func testEveryDetectedKindHasGuidance() {
        let kinds = ["Deno / TypeScript", "JavaScript / TypeScript", "Rust", "Swift", "Go", "Python", "Flutter / Dart", "Java / Kotlin", ".NET", "Workspace candidates"]
        for kind in kinds {
            let group = ProjectGroup(root: URL(fileURLWithPath: "/tmp/example"), kind: kind, entries: [])
            XCTAssertFalse(group.rebuildGuidance.isEmpty, kind)
            if kind != "Workspace candidates" {
                XCTAssertNotEqual(group.rebuildGuidance, "Rebuild from source using the project's documented command.", kind)
            }
        }
    }
}
