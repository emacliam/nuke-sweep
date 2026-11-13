import XCTest
@testable import Nuke
final class FolderListingTests: XCTestCase {
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nuke-list-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("large/deeper"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("large/deeper/data.bin"))
        return root
    }
    func testListingDoesNotMeasureDescendantsOrPretendTheirSizeIsZero() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let result = FolderListing.inspect(root, token: ScanCancellation())
        XCTAssertEqual(result.visited, 1)
        let folder = try XCTUnwrap(result.items.first)
        XCTAssertEqual(folder.name, "large")
        XCTAssertEqual(folder.measurementPending, true)
        XCTAssertTrue(folder.incomplete)
        let measured = FolderListing.measure(result.items, token: ScanCancellation(), excluding: { _ in false })
        XCTAssertEqual(measured.first?.size, 128)
        XCTAssertEqual(measured.first?.measurementPending, false)
        XCTAssertEqual(measured.first?.incomplete, false)
    }
    @MainActor func testExpansionListsNamesWhileBulkQueueIsBusy() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let entered = expectation(description:"bulk active"), release = DispatchSemaphore(value:0)
        let bulk = Task { await DiskWork.run("Held bulk") { entered.fulfill(); release.wait(); return true } }
        await fulfillment(of:[entered],timeout:2)
        let item = try XCTUnwrap(InventoryService.measure(root))
        let store = FolderTreeStore(); store.toggle(item)
        let deadline = Date().addingTimeInterval(1)
        while store.children[item.id] == nil, Date() < deadline { try await Task.sleep(for:.milliseconds(10)) }
        let children = store.children[item.id]
        release.signal(); _ = await bulk.value
        XCTAssertEqual(children?.map(\.name), ["large"])
        XCTAssertEqual(children?.first?.measurementPending, true)
        store.reset()
    }
    func testBudgetAndExclusionsStayExplicit() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at:root) }
        XCTAssertTrue(FolderListing.inspect(root, token:ScanCancellation(), limit:0).limited)
        XCTAssertTrue(FolderListing.inspect(root, token:ScanCancellation(), excluding: { $0.lastPathComponent == "large" }).items.isEmpty)
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:root.appendingPathComponent("large"))
        let alias = try XCTUnwrap(FolderListing.inspect(root,token:ScanCancellation()).items.first { $0.name == "alias" })
        XCTAssertTrue(alias.symlink); XCTAssertFalse(alias.directory)
    }
}
