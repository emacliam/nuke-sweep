import XCTest
@testable import Nuke

final class TreeSelectionTests: XCTestCase {
    private func item(_ path: String) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), size: 1, allocated: 1, directory: true, symlink: false, modified: nil, identity: nil, incomplete: false)
    }

    func testSelectingParentReplacesChildAndSelectingChildReplacesParent() {
        let project = item("/tmp/nuke-tree/project")
        let build = item("/tmp/nuke-tree/project/build")
        var selection: [String: DiskItem] = [:]

        selection = TreeSelection.updated(selection, toggling: build, on: true)
        XCTAssertEqual(Set(selection.keys), [build.url.path])

        selection = TreeSelection.updated(selection, toggling: project, on: true)
        XCTAssertEqual(Set(selection.keys), [project.url.path])

        selection = TreeSelection.updated(selection, toggling: build, on: true)
        XCTAssertEqual(Set(selection.keys), [build.url.path])
    }

    func testPathPrefixDoesNotTreatSiblingAsDescendant() {
        let project = item("/tmp/nuke-tree/project")
        let sibling = item("/tmp/nuke-tree/project-old")
        var selection: [String: DiskItem] = [:]
        selection = TreeSelection.updated(selection, toggling: project, on: true)
        selection = TreeSelection.updated(selection, toggling: sibling, on: true)
        XCTAssertEqual(Set(selection.keys), [project.url.path, sibling.url.path])
    }

    func testDeselectKeepsSiblings() {
        let first = item("/tmp/nuke-tree/a")
        let second = item("/tmp/nuke-tree/b")
        var selection: [String: DiskItem] = [:]
        selection = TreeSelection.updated(selection, toggling: first, on: true)
        selection = TreeSelection.updated(selection, toggling: second, on: true)
        selection = TreeSelection.updated(selection, toggling: first, on: false)
        XCTAssertEqual(Set(selection.keys), [second.url.path])
    }
}
