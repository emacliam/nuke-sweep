import XCTest
@testable import Nuke

/// Stop must empty the queue now, and asking twice must not queue twice.
final class DiskQueueTests: XCTestCase {
    func testARepeatedRequestSupersedesTheOneStillWaiting() async {
        let blocker = ScanCancellation()
        let gate = DispatchSemaphore(value: 0)
        async let busy: Void = DiskWork.run("Queue test blocker") { gate.wait() }
        try? await Task.sleep(for: .milliseconds(100))
        let first = ScanCancellation(), second = ScanCancellation()
        async let a: Bool = DiskWork.run("Queue test repeat", cancellation: first) { first.cancelled }
        try? await Task.sleep(for: .milliseconds(50))
        async let b: Bool = DiskWork.run("Queue test repeat", cancellation: second) { second.cancelled }
        try? await Task.sleep(for: .milliseconds(50))
        gate.signal()
        let (wasFirstCancelled, wasSecondCancelled) = await (a, b)
        _ = await busy
        _ = blocker
        XCTAssertTrue(wasFirstCancelled, "the older waiting request is superseded")
        XCTAssertFalse(wasSecondCancelled)
    }

    func testAStoppedJobRunsBeforeWorkQueuedAheadOfIt() async {
        let gate = DispatchSemaphore(value: 0)
        let order = OrderLog()
        async let busy: Void = DiskWork.run("Queue order blocker") { gate.wait() }
        try? await Task.sleep(for: .milliseconds(100))
        async let slow: Void = DiskWork.run("Queue order slow") { order.add("slow") }
        try? await Task.sleep(for: .milliseconds(30))
        let token = ScanCancellation()
        async let stopped: Void = DiskWork.run("Queue order stopped", cancellation: token) { order.add("stopped") }
        try? await Task.sleep(for: .milliseconds(30))
        token.cancel()
        gate.signal()
        _ = await (busy, slow, stopped)
        XCTAssertEqual(order.values, ["stopped", "slow"])
    }
}

private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ value: String) { lock.lock(); items.append(value); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
