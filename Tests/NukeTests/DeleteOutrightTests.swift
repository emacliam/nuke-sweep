import XCTest
@testable import Nuke

final class DeleteOutrightTests: XCTestCase {
    func testOnlyStillRebuildableItemsAreDeletedTheRestGoToTrash() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-outright-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deps = root.appendingPathComponent("app/node_modules"), notes = root.appendingPathComponent("app/notes")
        for (folder, file) in [(deps, "x/f.js"), (notes, "x/clip.mov")] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("x"), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 2000).write(to: folder.appendingPathComponent(file))
        }
        let scope = CleanupScope(root: root, identity: try XCTUnwrap(FileIdentity.read(root)))
        let items = try [deps, notes].map { try XCTUnwrap(InventoryService.measure($0)) }
        // Seal both through the normal review, as the app does.
        let reviewed = ReviewPlanner.prepare(items, scopes: [scope], openFiles: { [] }).items
        XCTAssertEqual(reviewed.count, 2)
        var trashed: [URL] = []
        let receipt = ReceiptService.moveToTrash(reviewed, proofs: [], runningAppPaths: [], allowedRoots: [scope],
                                                 deleteOutright: Set(reviewed.map(\.id)),
                                                 mover: { url in trashed.append(url); try FileManager.default.removeItem(at: url); return nil })
        XCTAssertTrue(receipt.items.allSatisfy(\.success), receipt.items.map(\.outcome).joined(separator: "; "))
        XCTAssertEqual(receipt.items.first { $0.originalPath == deps.path }?.outcome, "Deleted (rebuilds itself)")
        XCTAssertEqual(trashed.map(\.lastPathComponent), ["notes"], "a folder that is not rebuildable goes to Trash even if marked")
    }
}
