import XCTest
@testable import Nuke

final class PersistenceTests: XCTestCase {
    private func entry(_ name: String, size: Int64, incomplete: Bool) -> InventoryEntry {
        let url = URL(fileURLWithPath: "/tmp/nuke-persist/" + name)
        return InventoryEntry(
            item: DiskItem(url: url, size: size, allocated: size, directory: true, symlink: false, modified: nil, identity: nil, incomplete: incomplete),
            category: "Application caches",
            owner: name + " (inferred)",
            explanation: "Sample candidate",
            removable: true
        )
    }

    func testQuickPassRoundTripsThroughWorkspaceState() throws {
        let measured = Date(timeIntervalSince1970: 1_800_000_000)
        var quick = QuickScanState()
        quick.step = "Inspection finished"
        quick.measured = measured
        quick.entries = [entry("CacheOne", size: 1_024, incomplete: false), entry("CacheTwo", size: 2_048, incomplete: true)]
        quick.notes = ["Application caches: incomplete or unavailable."]
        quick.trashSize = 4_096
        quick.trashPartial = true

        let state = WorkspaceState(
            page: Page.findSpace.rawValue,
            root: URL(fileURLWithPath: "/tmp"),
            filters: [:],
            focusedItem: nil,
            snapshot: nil,
            measured: nil,
            quick: quick
        )
        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(restored.quick?.measured, measured)
        XCTAssertEqual(restored.quick?.entries.count, 2)
        XCTAssertEqual(restored.quick?.entries.first?.item.size, 1_024)
        XCTAssertEqual(restored.quick?.entries.last?.item.incomplete, true)
        XCTAssertEqual(restored.quick?.trashSize, 4_096)
        XCTAssertEqual(restored.quick?.trashPartial, true)
        XCTAssertEqual(restored.quick?.incomplete, true)
        XCTAssertEqual(restored.quick?.measuredBytes, 3_072)
        XCTAssertFalse(restored.quick?.stopped ?? true)
    }

    func testWorkspaceWithoutQuickPassStillDecodes() throws {
        // Older saved workspaces have no quick key. Optional decoding must keep them readable.
        let json = #"{"page":"Find space","root":"file:\/\/\/tmp\/","filters":{}}"#
        let restored = try JSONDecoder().decode(WorkspaceState.self, from: Data(json.utf8))
        XCTAssertNil(restored.quick)
        XCTAssertEqual(restored.page, Page.findSpace.rawValue)
    }
}
