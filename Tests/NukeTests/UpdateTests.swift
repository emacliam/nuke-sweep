import XCTest
@testable import Nuke
final class UpdateTests: XCTestCase {
    func testNumericVersionsAndOfficialReleaseLinks() {
        let release = PublicRelease(tag_name: "v0.10.0", html_url: "https://github.com/emacliam/nuke-sweep/releases/tag/v0.10.0", draft: false, prerelease: false)
        XCTAssertEqual(release.newer(than: "0.9.9"), true)
        XCTAssertEqual(release.newer(than: "0.10.0"), false)
        XCTAssertNil(release.newer(than: "unknown"))
        let foreign = PublicRelease(tag_name: "v0.10.0", html_url: "https://evil.example/download", draft: false, prerelease: false)
        XCTAssertNil(foreign.verifiedURL)
        XCTAssertNil(PublicRelease.components("v0.10-beta"))
        XCTAssertNil(PublicRelease(tag_name: "v1.0.0", html_url: "https://github.com/emacliam/nuke-sweep/releases/tag/v1.0.0", draft: false, prerelease: true).verifiedURL)
    }
}
