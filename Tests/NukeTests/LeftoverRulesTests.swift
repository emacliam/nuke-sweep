import XCTest
@testable import Nuke

final class LeftoverRulesTests: XCTestCase {
    func testDerivedDataWithMissingProjectIsALeftover() throws {
        let home = URL(fileURLWithPath: "/tmp/nuke-home-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let container = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/NukeTestApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container.appendingPathComponent("Build"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/tmp/gone-\(UUID().uuidString)/App.xcodeproj"], format: .xml, options: 0)
        try plist.write(to: container.appendingPathComponent("info.plist"))
        XCTAssertTrue(XcodeLeftovers.projectGone(container.appendingPathComponent("Build")))
        let alive = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/tmp"], format: .xml, options: 0)
        try alive.write(to: container.appendingPathComponent("info.plist"))
        XCTAssertFalse(XcodeLeftovers.projectGone(container.appendingPathComponent("Build")))
    }

    func testOlderJetBrainsVersionsAreLeftovers() throws {
        let home = URL(fileURLWithPath: "/tmp/nuke-home-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Caches/JetBrains")
        let old = root.appendingPathComponent("NukeTestIDE2024.1"), new = root.appendingPathComponent("NukeTestIDE2025.2")
        for url in [old, new] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: old); try? FileManager.default.removeItem(at: new) }
        XCTAssertTrue(JetBrainsLeftovers.olderVersion(old))
        XCTAssertFalse(JetBrainsLeftovers.olderVersion(new))
    }
}
