import XCTest
@testable import Nuke

final class DuplicateSelectionTests: XCTestCase {
    func item(_ name: String) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: "/fixture/" + name), size: 100, allocated: 100, directory: false, symlink: false, modified: nil, identity: nil, incomplete: false)
    }
    func testBatchReviewRetainsEveryChosenKeeper() throws {
        let a = item("a"), b = item("b"), c = item("c"), d = item("d")
        let groups = [DuplicateGroup(digest: "one", files: [a,b]), DuplicateGroup(digest: "two", files: [c,d])]
        let plan = try XCTUnwrap(DuplicateSelection.prepare(groups: groups, selected: ["one","two"], keepers: ["one":b.id]))
        XCTAssertEqual(plan.items.map(\.id), [a.id,d.id])
        XCTAssertEqual(plan.proofs.map { $0.keeper.id }, [b.id,c.id])
        XCTAssertTrue(Set(plan.items.map(\.id)).isDisjoint(with: plan.proofs.map { $0.keeper.id }))
    }
    func testStaleKeeperRefusesProposal() {
        let group = DuplicateGroup(digest: "one", files: [item("a"),item("b")])
        XCTAssertNil(DuplicateSelection.prepare(groups: [group], selected: ["one"], keepers: ["one":"missing"]))
    }
    func testUnselectedGroupsDoNotEnterReview() throws {
        let group = DuplicateGroup(digest: "one", files: [item("a"),item("b")])
        XCTAssertTrue(try XCTUnwrap(DuplicateSelection.prepare(groups: [group], selected: [], keepers: [:])).items.isEmpty)
    }
}
