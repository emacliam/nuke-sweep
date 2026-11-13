import XCTest
import NukeMetrics
@testable import Nuke

/// The menu-bar bar is the most glanced-at element in the app. It has to agree
/// with the alert the user configured, and it must never imply alarm at a fill
/// level the user has said is fine.
final class StoragePressureTests: XCTestCase {
    private let total: Int64 = 500_000_000_000

    private func pressure(freeGB: Double, thresholdGB: Double = 10) -> StoragePressure {
        StoragePressure.evaluate(free: Int64(freeGB * 1_000_000_000), total: total, thresholdGB: thresholdGB)
    }

    func testFreeSpaceAtOrBelowTheUsersThresholdIsLow() {
        XCTAssertEqual(pressure(freeGB: 10), .low, "At the threshold the user would be alerted, so the bar must agree.")
        XCTAssertEqual(pressure(freeGB: 4), .low)
        XCTAssertEqual(pressure(freeGB: 0), .low)
    }

    func testJustAboveTheThresholdIsTightRatherThanLow() {
        XCTAssertEqual(pressure(freeGB: 15), .tight)
        XCTAssertEqual(pressure(freeGB: 20), .tight)
    }

    /// The case that motivated this: a comfortable disk was drawn in the same
    /// alarming brand colour as a nearly-full one.
    func testComfortableSpaceIsNotPresentedAsAWarning() {
        XCTAssertEqual(pressure(freeGB: 120), .comfortable)
        XCTAssertFalse(pressure(freeGB: 120).isConcerning)
        XCTAssertEqual(pressure(freeGB: 120).tint, Theme.green)
    }

    /// 20.5 GB free clears a 10 GB threshold but is still 96% of a 500 GB disk.
    /// A cleanup utility calling that "comfortable" would be misleading.
    func testANearlyFullDiskIsNotComfortableEvenWhenItClearsTheThreshold() {
        XCTAssertEqual(pressure(freeGB: 20.5, thresholdGB: 10), .tight)
        XCTAssertTrue(pressure(freeGB: 20.5, thresholdGB: 10).isConcerning)
    }

    /// Proportional fullness may only hold a state back, never soften one the
    /// user's own threshold has already called low.
    func testProportionalRuleNeverOverridesTheUsersThreshold() {
        // 5 GB free on a tiny disk: proportionally fine, absolutely below threshold.
        let small = StoragePressure.evaluate(free: 5_000_000_000, total: 100_000_000_000, thresholdGB: 10)
        XCTAssertEqual(small, .low, "Below the configured threshold stays low regardless of proportion.")
    }

    /// Isolates the threshold from the proportional rule by holding the disk at a
    /// fill level that is never the deciding factor (200 GB free of 500 GB is 60%
    /// used), so only the user's setting moves the result.
    func testThresholdIsTakenFromTheUsersSettingNotAConstant() {
        func atRoomyDisk(thresholdGB: Double) -> StoragePressure {
            StoragePressure.evaluate(free: 200_000_000_000, total: total, thresholdGB: thresholdGB)
        }
        XCTAssertEqual(atRoomyDisk(thresholdGB: 10), .comfortable)
        XCTAssertEqual(atRoomyDisk(thresholdGB: 250), .low)
        XCTAssertEqual(atRoomyDisk(thresholdGB: 150), .tight)
    }

    func testAnUnreadableVolumeIsUnavailableRatherThanFull() {
        XCTAssertEqual(StoragePressure.evaluate(free: 0, total: 0, thresholdGB: 10), .unavailable)
        XCTAssertEqual(StoragePressure.evaluate(free: -1, total: total, thresholdGB: 10), .unavailable)
        XCTAssertFalse(StoragePressure.evaluate(free: 0, total: 0, thresholdGB: 10).isConcerning,
                       "A missing reading is not evidence of a problem.")
    }

    /// A nonsensical threshold must not collapse every disk into one state.
    func testAThresholdOfZeroDoesNotMakeEveryDiskLow() {
        XCTAssertEqual(pressure(freeGB: 100, thresholdGB: 0), .comfortable)
        XCTAssertEqual(pressure(freeGB: 0.5, thresholdGB: 0), .low)
    }

    /// Colour is never the only carrier of the state.
    func testEveryStateHasADistinctLabelAndSpokenForm() {
        let states: [StoragePressure] = [.comfortable, .tight, .low, .unavailable]
        let spoken = Set(states.map(\.spoken))
        XCTAssertEqual(spoken.count, states.count, "Each state needs its own spoken description.")
        for state in states { XCTAssertFalse(state.spoken.isEmpty) }
    }
}
