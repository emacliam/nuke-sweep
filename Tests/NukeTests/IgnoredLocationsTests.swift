import XCTest
@testable import Nuke

final class IgnoredLocationsTests: XCTestCase {
    func testProjectDiscoverySkipsIgnoredWorkspacesAndArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let previous = UserDefaults.standard.object(forKey: IgnoredLocations.key)
        defer {
            UserDefaults.standard.set(previous, forKey: IgnoredLocations.key)
            try? FileManager.default.removeItem(at: root)
        }
        let ignoredWorkspace = root.appendingPathComponent("ignored")
        let workspace = root.appendingPathComponent("visible")
        let ignoredArtifact = workspace.appendingPathComponent("node_modules")
        let visibleArtifact = workspace.appendingPathComponent("dist")
        for location in [ignoredWorkspace.appendingPathComponent("node_modules"), ignoredArtifact, visibleArtifact] {
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            try Data([1]).write(to: location.appendingPathComponent("payload"))
        }
        IgnoredLocations.add(ignoredWorkspace)
        IgnoredLocations.add(ignoredArtifact)

        let report = ProjectDiscovery.scan(root, token: ScanCancellation())
        XCTAssertEqual(report.projects.flatMap(\.entries).map { $0.item.url.path }, [visibleArtifact.path])
        XCTAssertTrue(ProjectDiscovery.scan(ignoredWorkspace, token: ScanCancellation()).projects.isEmpty)
    }

    func testIgnoredChildIsHiddenAndProtectsParentFromCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("keep")
        let sibling = root.appendingPathComponent("keeper")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: IgnoredLocations.key)
        defer {
            defaults.set(previous, forKey: IgnoredLocations.key)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: sibling)
        IgnoredLocations.add(folder)
        let scan = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(scan.items.map(\.name), ["keeper"])
        let parent = DiskItem(url: root, size: 1, allocated: 1, directory: true, symlink: false,
                              modified: nil, identity: FileIdentity.read(root), incomplete: false)
        XCTAssertThrowsError(try CleanupSafety.validate(parent)) { error in
            XCTAssertEqual(error.localizedDescription, "This item is ignored or contains an ignored location.")
        }
        XCTAssertTrue(IgnoredLocations.overlaps(root, in: [folder.path]))
        XCTAssertFalse(IgnoredLocations.overlaps(sibling, in: [folder.path]))
    }
}
