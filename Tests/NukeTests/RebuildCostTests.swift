import XCTest
@testable import Nuke

/// Rebuild cost is what turns a size list into a decision. These pin the one
/// distinction that must never blur: storage that regenerates versus storage that
/// does not.
final class RebuildCostTests: XCTestCase {
    func testArchivesAreIrreplaceableAndNeverPresentedAsCheap() {
        let cost = RebuildCost.forCacheRule("archives")
        XCTAssertEqual(cost.effort, .irreplaceable)
        XCTAssertNil(cost.action, "There is no command that brings an archive back.")
        XCTAssertFalse(cost.summary.hasPrefix("Back in"), "An irreplaceable item must not be phrased as a wait.")
    }

    func testPackageCachesAreCheapToRestore() {
        for id in ["npm", "pip", "homebrew", "go"] {
            XCTAssertLessThanOrEqual(RebuildCost.forCacheRule(id).effort, .quick, "\(id) should be quick to restore")
        }
    }

    func testBuildOutputIsASlowerRestoreThanADownloadCache() {
        XCTAssertGreaterThan(RebuildCost.forCacheRule("xcode").effort, RebuildCost.forCacheRule("npm").effort)
    }

    func testAnUncataloguedRuleIsUnknownRatherThanGuessed() {
        XCTAssertEqual(RebuildCost.forCacheRule("something-nobody-catalogued").effort, .unknown)
    }

    func testEvidenceFallbackRecognisesCommonProjectFolders() {
        XCTAssertEqual(RebuildCost.forEvidence(nil, name: "node_modules").effort, .slow)
        XCTAssertEqual(RebuildCost.forEvidence(nil, name: "Pods").effort, .slow)
        XCTAssertEqual(RebuildCost.forEvidence(nil, name: "target").effort, .slow)
        XCTAssertNotNil(RebuildCost.forEvidence(nil, name: "node_modules").action)
    }

    func testEffortOrderingIsMeaningful() {
        XCTAssertLessThan(RebuildCost.Effort.trivial, RebuildCost.Effort.quick)
        XCTAssertLessThan(RebuildCost.Effort.quick, RebuildCost.Effort.slow)
        XCTAssertLessThan(RebuildCost.Effort.slow, RebuildCost.Effort.irreplaceable)
    }

    /// Nothing in the copy may imply an item is safe to remove.
    func testNoCostCopyClaimsSafety() throws {
        let ids = ["xcode", "npm", "gradle", "archives", "simulator", "huggingface", "unknown-id"]
        for id in ids {
            let cost = RebuildCost.forCacheRule(id)
            XCTAssertNoThrow(try AIOutputLimits.advice(cost.summary), "\(id) copy must not claim safety")
            XCTAssertNoThrow(try AIOutputLimits.advice(cost.estimate))
        }
    }
}
