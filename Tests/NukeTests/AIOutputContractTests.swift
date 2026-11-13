import XCTest
@testable import Nuke

final class AIOutputContractTests: XCTestCase {
    func testKeepWinsOverSelect() {
        let context = AIPlanContext(instruction: "keep build", scopeLabel: nil, scopePolicy: nil, items: [.init(name: "build", sizeBytes: 1, kind: "folder", evidence: "Build output", blocked: false)])
        let result = AIPlanSuggestion(select: ["build"], keep: ["build"], exclude: [], reasoning: "x", risks: [], confidence: 1).resolved(against: context)
        XCTAssertTrue(result.selected.isEmpty)
        XCTAssertEqual(result.kept, ["build"])
    }
    func testUnknownNamesAndDuplicateDisplayNamesCannotAuthorizeAnItem() {
        let context = AIPlanContext(instruction: "clean", scopeLabel: nil, scopePolicy: nil, items: [
            .init(name: "build", sizeBytes: 1, kind: "folder", evidence: "Build output", blocked: false),
            .init(name: "build", sizeBytes: 2, kind: "folder", evidence: "Protected", blocked: true)
        ])
        let result = AIPlanSuggestion(select: ["build", "unlisted"], keep: [], exclude: [], reasoning: "x", risks: [], confidence: 1).resolved(against: context)
        XCTAssertTrue(result.selected.isEmpty)
    }
    func testUnsupportedSafetyGuaranteeIsRejected() {
        XCTAssertThrowsError(try AISuggestion.parse(#"{"category":"cache","confidence":1,"explanation":"Completely safe to delete.","rebuild":null,"risks":[]}"#))
    }
    func testOversizedIndividualFieldsAreRejected() throws {
        let long = String(repeating: "x", count: 100_000)
        let data = try JSONSerialization.data(withJSONObject: ["category":"cache", "confidence":0.6,"explanation":"Generated output", "rebuild":long,"risks":[long]])
        XCTAssertThrowsError(try AISuggestion.parse(String(decoding: data, as: UTF8.self)))
    }
    func testOversizedPlanArraysAreRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: ["select":(0..<5000).map { "item-\($0)" },"keep":[],"exclude":[],"reasoning":"x","risks":[],"confidence":0.6])
        XCTAssertThrowsError(try AIPlanSuggestion.parse(String(decoding:data,as:UTF8.self)))
    }
    func testOversizedGrowthFieldsAreRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: ["summary":"Growth","drivers":[String(repeating:"x",count:100_000)],"caveats":[],"confidence":0.5])
        XCTAssertThrowsError(try AIGrowthSummary.parse(String(decoding:data,as:UTF8.self)))
    }
}
