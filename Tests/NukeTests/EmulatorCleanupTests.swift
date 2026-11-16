import XCTest
@testable import Nuke

final class EmulatorCleanupTests: XCTestCase {
    let id = "A940DB23-EC7B-4B19-8FC3-639ACB26DE90"
    func json(_ state: String) -> String {
        "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-18-0\":[{\"udid\":\"\(id)\",\"name\":\"Test phone\",\"state\":\"\(state)\",\"isAvailable\":false}]}}"
    }
    func testRuntimeInventoryOnlyOffersCommandsForDeletableUUIDs() throws {
        let id = "4B539264-A677-42C5-B3B7-5DED42E35F58"
        let json = """
        {
          "one": {"identifier":"\(id)","version":"26.5","lastUsedAt":"2026-11-11T18:18:04Z","deletable":true},
          "two": {"identifier":"all","version":"17.0","deletable":true},
          "three": {"identifier":"5A151310-D165-461E-93A6-F9555692958B","version":"17.1","deletable":false}
        }
        """
        let runtimes = try XCTUnwrap(EmulatorCleanup.decodeRuntimes(json))
        XCTAssertEqual(runtimes.first?.id, id)
        XCTAssertEqual(EmulatorCleanup.outdatedRuntimeIDs("Would delete D: \(id) iOS (26.5)"), [id])
        XCTAssertTrue(EmulatorCleanup.outdatedRuntimeIDs("Kept \(id)").isEmpty)
        XCTAssertEqual(runtimes.compactMap(\.removalCommand), ["xcrun simctl runtime delete " + id])
    }

    func testFirstLaunchRequirementNeverInvokesSimctl() {
        var calls = 0
        let inventory = EmulatorCleanup.simulators { _, _ in calls += 1; return .init(output: "Setup required", status: 1) }
        XCTAssertEqual(calls, 1); XCTAssertTrue(inventory.devices.isEmpty)
        XCTAssertTrue(inventory.note.contains("Xcode setup"))
    }
    func testLiveBootedDeviceCannotBeDeleted() throws {
        let stale = try XCTUnwrap(EmulatorCleanup.decode(json("Shutdown")).devices.first)
        var deleted = false
        let message = EmulatorCleanup.delete(stale) { _, args in
            if args.contains("delete") { deleted = true }
            return .init(output: args.contains("devices") ? self.json("Booted") : "", status: 0)
        }
        XCTAssertFalse(deleted); XCTAssertTrue(message.message.contains("Refused"))
    }
    func testShutdownDeviceUsesExactIdentifierAfterLiveCheck() throws {
        let device = try XCTUnwrap(EmulatorCleanup.decode(json("Shutdown")).devices.first)
        var calls: [[String]] = []
        let message = EmulatorCleanup.delete(device) { _, args in
            calls.append(args)
            return .init(output: args.contains("devices") ? self.json("Shutdown") : "", status: 0)
        }
        XCTAssertEqual(calls.last, ["simctl", "delete", id]); XCTAssertTrue(message.success)
    }
    func testMalformedInventoryFailsClosed() {
        XCTAssertTrue(EmulatorCleanup.decode("bad response").devices.isEmpty)
        XCTAssertTrue(EmulatorCleanup.decode(json("Unknown")).devices.allSatisfy { !$0.canDelete })
    }
    func testAndroidRunningAndUnknownProcessesBlockCleanup() {
        XCTAssertFalse(EmulatorCleanup.androidIdle(.init(output: "", status: 1)))
        XCTAssertFalse(EmulatorCleanup.androidIdle(.init(output: "", status: 0)))
        XCTAssertFalse(EmulatorCleanup.androidIdle(.init(output: "/usr/bin/login\n/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64", status: 0)))
        XCTAssertTrue(EmulatorCleanup.androidIdle(.init(output: "/usr/bin/login\n/usr/bin/swift", status: 0)))
    }
    func testOnlySnapshotDirectoryQualifies() {
        let home = URL(fileURLWithPath: "/tmp/test-home")
        XCTAssertTrue(EmulatorCleanup.isAndroidSnapshot(home.appendingPathComponent(".android/avd/Pixel.avd/snapshots"), home: home))
        XCTAssertFalse(EmulatorCleanup.isAndroidSnapshot(home.appendingPathComponent(".android/avd/Pixel.avd"), home: home))
        XCTAssertFalse(EmulatorCleanup.isAndroidSnapshot(home.appendingPathComponent(".android/avd/Pixel.avd/userdata"), home: home))
    }
}
