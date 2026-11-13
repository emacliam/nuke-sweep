import XCTest
@testable import Nuke

/// Progress reporting sits in the innermost scan loops, so its per-call cost is
/// multiplied by every visited entry. These are regression gates on that cost,
/// not benchmarks of the filesystem: they run inside a real `DiskWork` job so
/// `report` sees a live worker handle, and they assert throughput budgets that a
/// reintroduced per-call lock or per-call string build would blow through.
final class ScanProgressPerformanceTests: XCTestCase {
    private static let calls = 1_000_000

    /// A rejected progress tick must not take the scheduler lock, parse an id, or
    /// build its label. One million rejections should cost well under a second;
    /// the pre-fix implementation parsed a UUID and locked on every call.
    func testRejectedProgressTicksStayCheap() async {
        let elapsed = await DiskWork.run("Progress cost fixture") { () -> Double in
            let started = DispatchTime.now().uptimeNanoseconds
            for index in 0..<Self.calls {
                DiskWork.report(path: "visiting " + String(index), visited: index)
            }
            return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        }
        print("NUKE_REPORT_BENCH calls=\(Self.calls) seconds=\(elapsed) per_call_ns=\(elapsed / Double(Self.calls) * 1_000_000_000)")
        XCTAssertLessThan(elapsed, 1.0, "One million rejected progress ticks took \(elapsed)s; the reject path regressed.")
    }

    /// The label is only meaningful on an accepted tick. An autoclosure keeps the
    /// concatenation out of the reject path entirely, so a deliberately expensive
    /// label must not change the cost of a million rejected calls.
    func testProgressLabelIsNotBuiltWhenThrottled() async {
        let built = Counter()
        let elapsed = await DiskWork.run("Label cost fixture") { () -> Double in
            let started = DispatchTime.now().uptimeNanoseconds
            for index in 0..<Self.calls {
                DiskWork.report(path: built.expensiveLabel(index), visited: index)
            }
            return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        }
        let count = built.value
        print("NUKE_REPORT_BENCH labels_built=\(count) of \(Self.calls) seconds=\(elapsed)")
        // Throttled to five ticks a second per worker, so a sub-second loop should
        // build a handful of labels at most -- never one per call.
        XCTAssertLessThan(count, 100, "\(count) labels were built for \(Self.calls) calls; the label is no longer lazy.")
    }

    /// Reporting from the scan loops must not serialize the two lanes against each
    /// other. A worker spinning progress ticks cannot delay an interactive listing.
    func testProgressReportingDoesNotBlockTheInteractiveLane() async throws {
        let spinning = expectation(description: "bulk reporting")
        let stop = ScanCancellation()
        let bulk = Task {
            await DiskWork.run("Reporting bulk", cancellation: stop) { () -> Bool in
                spinning.fulfill()
                var index = 0
                while !stop.cancelled {
                    DiskWork.report(path: "visiting " + String(index), visited: index)
                    index += 1
                }
                return true
            }
        }
        await fulfillment(of: [spinning], timeout: 2)
        let began = Date()
        let listed = await DiskWork.run("List folder", lane: .interactive) { Date().timeIntervalSince(began) }
        stop.cancel()
        _ = await bulk.value
        XCTAssertLessThan(listed, 0.5, "Interactive listing waited \(listed)s behind a reporting bulk scan.")
    }

    private final class Counter {
        private(set) var value = 0
        func expensiveLabel(_ index: Int) -> String {
            value += 1
            return "visiting " + String(index) + " " + String(repeating: "x", count: 64)
        }
    }
}
