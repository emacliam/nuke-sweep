import XCTest
@testable import Nuke

final class DiskLaneTests: XCTestCase {
    func testInteractiveListingDoesNotWaitForBulkScan() async throws {
        let entered = expectation(description: "bulk running"), release = DispatchSemaphore(value: 0)
        let bulk = Task { await DiskWork.run("Bulk fixture") { entered.fulfill(); release.wait(); return true } }
        await fulfillment(of: [entered], timeout: 2)
        let began = Date()
        let completed = expectation(description: "interactive completed")
        let interactive = Task { await DiskWork.run("List folder", lane: .interactive) { completed.fulfill(); return Date().timeIntervalSince(began) } }
        await fulfillment(of: [completed], timeout: 1)
        release.signal()
        let delay = await interactive.value; _ = await bulk.value
        XCTAssertLessThan(delay, 0.5)
    }
    func testGlobalStopCancelsBothLanesAndQueuedJobs() async throws {
        let entered = expectation(description: "both lanes"); entered.expectedFulfillmentCount = 2
        let a = ScanCancellation(), b = ScanCancellation(), queued = ScanCancellation()
        func work(_ token: ScanCancellation) -> Bool {
            entered.fulfill()
            let deadline = Date().addingTimeInterval(2)
            while !token.cancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            return token.cancelled
        }
        let bulk = Task { await DiskWork.run("Bulk", cancellation: a) { work(a) } }
        let listing = Task { await DiskWork.run("Listing", lane: .interactive, cancellation: b) { work(b) } }
        await fulfillment(of: [entered], timeout: 2)
        let pending = Task { await DiskWork.run("Queued", cancellation: queued) { queued.cancelled } }
        try await Task.sleep(for: .milliseconds(20)); DiskWork.cancelAll()
        let results = await (bulk.value, listing.value, pending.value)
        XCTAssertTrue(results.0); XCTAssertTrue(results.1); XCTAssertTrue(results.2)
    }
}
