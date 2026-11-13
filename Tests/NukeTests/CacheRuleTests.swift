import XCTest
@testable import Nuke

final class CacheRuleTests: XCTestCase {
    func testCacheRulesAreUniqueAndRelative() {
        let rules = CacheRule.all
        XCTAssertGreaterThanOrEqual(rules.count, 18)
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
        XCTAssertEqual(Set(rules.map(\.relativePath)).count, rules.count)
        for rule in rules {
            XCTAssertFalse(rule.name.isEmpty, rule.id)
            XCTAssertFalse(rule.detail.isEmpty, rule.id)
            XCTAssertFalse(rule.symbol.isEmpty, rule.id)
            XCTAssertFalse(rule.relativePath.hasPrefix("/"), rule.id)
            XCTAssertTrue(rule.url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path), rule.id)
        }
    }

    func testNewDeveloperRulesArePresent() {
        let ids = Set(CacheRule.all.map(\.id))
        for id in ["bun", "deno", "uv", "poetry", "cargo", "maven", "nuget", "cocoapods", "huggingface"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }
}
