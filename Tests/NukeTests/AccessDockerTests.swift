import XCTest
@testable import Nuke

final class AccessDockerTests: XCTestCase {
    func fixture() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().appendingPathComponent("nuke-access-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testChosenFolderAllowsChildrenButProtectsRootAndRejectsUnknownScope() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("review.txt"); try Data("review".utf8).write(to: file)
        let item = try XCTUnwrap(InventoryService.measure(file))
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        XCTAssertThrowsError(try CleanupSafety.validate(item))
        XCTAssertNoThrow(try CleanupSafety.validate(item, allowedRoots: [scope]))
        XCTAssertThrowsError(try CleanupSafety.validate(try XCTUnwrap(InventoryService.measure(root)), allowedRoots: [scope]))
        let partial = DiskItem(url: file, size: item.size, allocated: item.allocated, directory: false, symlink: false, modified: nil, identity: item.identity, incomplete: true)
        XCTAssertThrowsError(try CleanupSafety.validate(partial, allowedRoots: [scope]))
    }
    func testChangedGrantAndSymlinkParentCannotExpandScope() throws {
        let root = try fixture(), other = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: other) }
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let external = other.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: external)
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        let escapedItem = try XCTUnwrap(InventoryService.measure(link.appendingPathComponent("keep.txt")))
        XCTAssertThrowsError(try CleanupSafety.validate(escapedItem, allowedRoots: [scope]))
        let moved = root.appendingPathExtension("old")
        try FileManager.default.moveItem(at: root, to: moved)
        defer { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertFalse(scope.valid)
    }
    func testProtectedTreeCannotBeReachedThroughAnAlias() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let protected = root.appendingPathComponent("protected/Data")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        let file = protected.appendingPathComponent("Docker.raw"); try Data("keep".utf8).write(to: file)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("protected"))
        XCTAssertTrue(CleanupSafety.overlapsProtectedTree(alias.appendingPathComponent("Data/Docker.raw"), tree: root.appendingPathComponent("protected")))
        XCTAssertFalse(CleanupSafety.overlapsProtectedTree(alias, tree: root.appendingPathComponent("protected")), "Removing the alias itself does not remove the target")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testRememberedRootCannotBeRemovedThroughAnotherSpelling() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inner = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let scopes = [CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root))), CleanupScope(root: inner, identity: try XCTUnwrap(FileIdentity.read(inner)))]
        let item = try XCTUnwrap(InventoryService.measure(alias.appendingPathComponent("chosen")))
        XCTAssertThrowsError(try CleanupSafety.validate(item, allowedRoots: scopes))
    }
    func testBookmarkRestoredRootStillAuthorizesItsChildren() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("review.txt"); try Data("review".utf8).write(to: file)
        let data = try root.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scope = CleanupScope(root: resolved, identity: try XCTUnwrap(FileIdentity.read(root)))
        XCTAssertTrue(scope.valid)
        XCTAssertNoThrow(try CleanupSafety.validate(try XCTUnwrap(InventoryService.measure(file)), allowedRoots: [scope]))
    }
    func testSystemAndBroadRootsCannotBeGranted() {
        for path in ["/", "/System/Library", "/Library/Caches", "/Users", "/usr/local", "/Applications", "/private/var/db"] { XCTAssertFalse(CleanupSafety.canGrant(URL(fileURLWithPath: path)), path) }
    }
    func testStoppedDockerDoesNotReportEmptyUsageAsLiveOrStartEngine() {
        var commands: [[String]] = []
        let report = DockerInspection.inspect { args, _ in
            commands.append(args)
            return args == ["context", "show"] ? .init(output: "desktop-linux", status: 0) : .init(output: "Cannot connect to the Docker daemon", status: 1)
        }
        XCTAssertEqual(commands.count, 2)
        XCTAssertFalse(report.reachable)
        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertTrue(report.note?.contains("No engine was started") == true)
        XCTAssertFalse(commands.joined().contains("prune"))
    }
    func testDockerDeniedSocketAndLiveUsageAreDistinct() {
        let denied = DockerInspection.inspect { args, _ in args == ["context", "show"] ? .init(output: "remote", status: 0) : .init(output: "permission denied", status: 1) }
        XCTAssertTrue(denied.note?.contains("Full Disk Access does not grant Docker API access") == true)
        let live = DockerInspection.inspect { args, _ in args == ["context", "show"] ? .init(output: "desktop-linux", status: 0) : .init(output: "{\"Type\":\"Images\",\"TotalCount\":2,\"Size\":\"1GB\",\"Reclaimable\":\"0B\"}", status: 0) }
        XCTAssertTrue(live.reachable); XCTAssertEqual(live.rows.first?.total, "2")
    }
    func testChartInspectorSelectsRealNearestPoint() {
        let dates = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 30)]
        XCTAssertEqual(ChartInspection.nearest(dates, date: nil, dateOf: { $0 }), dates[2])
        XCTAssertEqual(ChartInspection.nearest(dates, date: Date(timeIntervalSince1970: 12), dateOf: { $0 }), dates[1])
    }
}
