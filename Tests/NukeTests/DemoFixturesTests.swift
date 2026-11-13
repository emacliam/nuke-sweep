import XCTest
@testable import Nuke

@MainActor
final class DemoFixturesTests: XCTestCase {
    func testFixturesAreDeterministicAndInMemoryOnly() {
        let model = AppModel(restoring: false)
        DemoFixtures.apply(to: model)
        XCTAssertEqual(model.activities.count, 3)
        XCTAssertEqual(model.features.scans.count, 2)
        XCTAssertEqual(Set(model.features.scans.map(\.root)), [DemoFixtures.rootPath])
        XCTAssertEqual(model.features.scans.first?.total, 2_743_000_000)
        XCTAssertEqual(model.activities.first?.title, "Cleanup")
        XCTAssertFalse(model.features.historyLoading)
        XCTAssertEqual(model.caches.count, 4)
        XCTAssertEqual(model.processes.count, 3)
        XCTAssertEqual(model.listeningPorts.count, 2)
        XCTAssertEqual(model.docker.count, 3)
        XCTAssertEqual(model.dockerVolumes.count, 2)
        XCTAssertTrue(model.dockerReachable)
        XCTAssertTrue(model.features.developerScopes.isEmpty)
    }
}
