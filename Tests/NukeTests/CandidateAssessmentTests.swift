import XCTest
@testable import Nuke
final class CandidateAssessmentTests: XCTestCase {
    func item(_ path: String = "/tmp/nuke-assessment/build", incomplete: Bool = false) -> DiskItem {
        .init(url:URL(fileURLWithPath:path),size:10,allocated:10,directory:true,symlink:false,modified:nil,identity:nil,incomplete:incomplete)
    }
    let generated = CleanupEvidence(kind:.buildOutput,detail:"Generated output by folder name",rebuild:"Rebuild the project.",gitIgnored:false)
    func testUncertaintyNeverBecomesAuthorization() {
        let assessment = CandidateAssessment.make(item(), evidence:generated)
        XCTAssertEqual(assessment.state,.reviewable)
        XCTAssertTrue(assessment.canSelect)
        XCTAssertTrue(assessment.unknowns.contains { $0.contains("not established") })
        XCTAssertTrue(assessment.consequences.contains { $0.contains("Trash") })
        XCTAssertEqual(CandidateAssessment.make(item(), evidence:nil).state,.checking)
        XCTAssertFalse(CandidateAssessment.make(item(), evidence:nil).canSelect)
        XCTAssertEqual(CandidateAssessment.make(item(incomplete:true),evidence:generated).state,.measurementNeeded)
    }
    func testSensitivePathsAndScopeBlocksWinOverGeneratedEvidence() {
        XCTAssertEqual(CandidateAssessment.make(item("/tmp/.aws/build"),evidence:generated).state,.protected)
        XCTAssertFalse(CandidateAssessment.make(item(),evidence:generated,scopeBlocked:true).canSelect)
    }
    func testIDsAreStableDistinctAndDoNotExposePaths() {
        let a = CandidateAssessment.make(item(),evidence:generated), b = CandidateAssessment.make(item("/tmp/other/build"),evidence:generated)
        XCTAssertEqual(a.id,CandidateAssessment.make(item(),evidence:nil).id)
        XCTAssertNotEqual(a.id,b.id); XCTAssertFalse(a.id.contains("/tmp"))
    }
}

extension CandidateAssessmentTests {
    func testAIPlansResolveOpaqueIDsRatherThanDuplicateNames() {
        let context = AIPlanContext(instruction:"clean generated folders",scopeLabel:nil,scopePolicy:nil,items:[
            .init(name:"build",sizeBytes:10,kind:"folder",evidence:"Build output",blocked:false,id:"item-first"),
            .init(name:"build",sizeBytes:20,kind:"folder",evidence:"Build output",blocked:false,id:"item-second")])
        let suggestion = AIPlanSuggestion(select:["item-first","item-second","build"],keep:["item-second"],exclude:[],reasoning:"Review generated files.",risks:[],confidence:1)
        let result = suggestion.resolved(against:context)
        XCTAssertEqual(result.selectedIDs,["item-first"])
        XCTAssertEqual(result.selected,["build"])
        XCTAssertEqual(result.omitted,["build"])
    }
    func testAISelectionCannotPromoteProtectedEvidence() {
        let context = AIPlanContext(instruction:"clean everything",scopeLabel:nil,scopePolicy:nil,items:[.init(name:"private",sizeBytes:10,kind:"folder",evidence:"Protected",blocked:true,id:"item-protected")])
        let result = AIPlanSuggestion(select:["item-protected"],keep:[],exclude:[],reasoning:"A suggestion.",risks:[],confidence:1).resolved(against:context)
        XCTAssertTrue(result.selectedIDs.isEmpty); XCTAssertEqual(result.omitted,["item-protected"])
    }
}
