import XCTest
@testable import Nuke

/// The review promises "open Trash and choose Put Back". These pin the ordinary
/// cases where that promise is false, because discovering it afterwards — when
/// the only copy is in Trash and Put Back is greyed out — is the worst moment.
final class RestorePreflightTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-restore-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func make(_ relative: String, directory: Bool = true) throws -> DiskItem {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if directory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        else { try Data("x".utf8).write(to: url) }
        return DiskItem(url: url, size: 1, allocated: 1, directory: directory, symlink: false,
                        modified: Date(), identity: nil, incomplete: false)
    }

    func testAnOrdinaryItemIsRestorable() throws {
        let item = try make("project/build")
        let report = RestorePreflight.inspect([item])
        XCTAssertTrue(report.allRestorable)
        XCTAssertNil(report.findings.first?.reason)
    }

    /// The case worth catching: trashing a folder and something inside it in the
    /// same pass leaves the inner item with nowhere to go back to.
    func testAnItemWhoseAncestorIsAlsoBeingCleanedIsNotRestorable() throws {
        let parent = try make("project")
        let child = try make("project/build")
        let report = RestorePreflight.inspect([parent, child])
        XCTAssertFalse(report.allRestorable)
        let flagged = report.findings.first { $0.item.id == child.id }
        XCTAssertEqual(flagged?.outlook.isRestorable, false)
        XCTAssertTrue(flagged?.reason?.contains("will not exist") ?? false)
        // The ancestor itself is fine: its own parent is untouched.
        XCTAssertTrue(report.findings.first { $0.item.id == parent.id }?.outlook.isRestorable ?? false)
    }

    func testOrderInTheBatchDoesNotChangeTheAnswer() throws {
        let parent = try make("project")
        let child = try make("project/build")
        let forward = RestorePreflight.inspect([parent, child]).manualOnly.map(\.id)
        let reversed = RestorePreflight.inspect([child, parent]).manualOnly.map(\.id)
        XCTAssertEqual(forward, reversed)
    }

    /// A sibling with a shared name prefix is not an ancestor.
    func testASiblingWithASharedPrefixIsNotTreatedAsAnAncestor() throws {
        let a = try make("build")
        let b = try make("build-output")
        XCTAssertTrue(RestorePreflight.inspect([a, b]).allRestorable)
    }

    func testAReadOnlyParentMeansNothingCanBeMovedBack() throws {
        let item = try make("locked/build")
        let report = RestorePreflight.inspect([item], writable: { _ in false })
        XCTAssertFalse(report.allRestorable)
        XCTAssertTrue(report.findings.first?.reason?.contains("not writable") ?? false)
    }

    func testAMissingParentIsReportedAsUnknownRatherThanRestorable() {
        let absent = DiskItem(
            url: root.appendingPathComponent("gone/child"),
            size: 1, allocated: 1, directory: true, symlink: false,
            modified: nil, identity: nil, incomplete: false
        )
        let report = RestorePreflight.inspect([absent])
        XCTAssertFalse(report.allRestorable)
        XCTAssertTrue(report.findings.first?.reason?.contains("could not be read") ?? false)
    }

    func testAnEmptySelectionIsVacuouslyFine() {
        let report = RestorePreflight.inspect([])
        XCTAssertTrue(report.isEmpty)
        XCTAssertTrue(report.allRestorable)
    }

    /// This is advice, not a veto: Finder's Put Back may still work.
    func testManualOnlyCopyDoesNotClaimTheItemCannotBeRecovered() throws {
        let parent = try make("project")
        let child = try make("project/build")
        let report = RestorePreflight.inspect([parent, child])
        for finding in report.manualOnly {
            let reason = try XCTUnwrap(finding.reason)
            XCTAssertFalse(reason.lowercased().contains("cannot be recovered"))
            XCTAssertNoThrow(try AIOutputLimits.advice(reason))
        }
    }
}
