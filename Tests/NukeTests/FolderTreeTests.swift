import XCTest
@testable import Nuke

final class FolderTreeTests: XCTestCase {
    @MainActor
    func testScopeTreeSkipsExcludedChildren() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-scope-tree-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 64).write(to: root.appendingPathComponent("keep.txt"))
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("skip.txt"))

        let scope = DeveloperScope(label: "Fixture", path: root.path, cleanupAllowed: true, exclusions: ["skip.txt"])
        let item = DiskItem(url: root, size: 192, allocated: 192, directory: true, symlink: false, modified: nil, identity: FileIdentity.read(root), incomplete: false)
        let store = FolderTreeStore()
        store.configure(isExcluded: scope.isExcluded)
        store.toggle(item)
        let deadline = Date().addingTimeInterval(8)
        while store.loading.contains(item.id), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }

        XCTAssertEqual(store.children[item.id]?.map(\.name), ["keep.txt"])
        XCTAssertTrue(scope.blocksSelection(item))
    }

    @MainActor
    func testExpandingFolderLoadsOnlyItsDirectChildren() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-tree-" + UUID().uuidString)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 64).write(to: root.appendingPathComponent("first.txt"))
        try Data(repeating: 1, count: 128).write(to: nested.appendingPathComponent("second.txt"))

        let item = DiskItem(url: nested, size: 128, allocated: 128, directory: true, symlink: false, modified: nil, identity: FileIdentity.read(nested), incomplete: false)
        let store = FolderTreeStore()
        store.toggle(item)
        let deadline = Date().addingTimeInterval(8)
        while store.loading.contains(item.id), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let children = store.children[item.id] ?? []
        XCTAssertEqual(children.map(\.name), ["second.txt"])
        XCTAssertEqual(children.first?.size, 128)
        XCTAssertTrue(store.expanded.contains(item.id))
        XCTAssertFalse(store.partial.contains(item.id))
    }
}
