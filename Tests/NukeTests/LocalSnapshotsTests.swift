import XCTest
@testable import Nuke

final class LocalSnapshotsTests: XCTestCase {
    func testSystemUpdateSnapshotsDoNotEnableTimeMachineThinning() {
        let listing = """
        Snapshots for volume group containing disk /:
        com.apple.os.update-MSUPrepareUpdate
        """
        let systemOnly = LocalSnapshots.parse(listing)
        XCTAssertTrue(systemOnly.timeMachine.isEmpty)
        XCTAssertEqual(systemOnly.otherCount, 1)

        let timeMachine = "com.apple.TimeMachine.2026-11-13-090000.local"
        let mixed = LocalSnapshots.parse(listing + "\n" + timeMachine)
        XCTAssertEqual(mixed.timeMachine, [timeMachine])
        XCTAssertEqual(mixed.otherCount, 1)
    }
}
