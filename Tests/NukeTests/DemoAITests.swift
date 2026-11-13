import XCTest
@testable import Nuke

@MainActor
final class DemoAITests: XCTestCase {
    func testDemoAIConfigurationIsLocalAndNonPersisting() {
        let ai = AISettings()
        let before = UserDefaults.standard.bool(forKey: "nuke.ai.enabled")
        ai.applyDemoConfiguration()
        XCTAssertTrue(ai.enabled)
        XCTAssertTrue(ai.offlineOnly)
        XCTAssertEqual(ai.providers.count, 1)
        XCTAssertEqual(ai.activeProvider.flavor, .local)
        XCTAssertEqual(ai.activeProvider.name, "Demo local model")
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "nuke.ai.enabled"), before)
    }
}
