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
