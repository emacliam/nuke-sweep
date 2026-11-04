import XCTest
@testable import Nuke

final class ScannerTests: XCTestCase {
    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testNestedFilesAndLargestFirst() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 3000).write(to: nested.appendingPathComponent("large"))
        try Data(repeating: 0, count: 20).write(to: root.appendingPathComponent("small"))
        let result = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(result.logical, 3020)
        XCTAssertEqual(result.items.map(\.name), ["nested", "small"])
        XCTAssertEqual(result.skipped, 0)
        XCTAssertFalse(result.limited)
    }
    func testSymlinksAreNotFollowed() throws {
        let root = try fixture(); let external = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        try Data(repeating: 1, count: 1_000_000).write(to: external.appendingPathComponent("outside"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: external)
        let result = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].symlink)
        XCTAssertLessThan(result.logical, 1000)
    }
    func testSymlinkRootIsRejected() throws {
        let root = try fixture(); let target = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: target) }
        let link = root.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let result = DiskScanner.scan(link, cancellation: ScanCancellation())
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.items.isEmpty)
    }
    func testCancelledAndBudgetedScansArePartial() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<10 { try Data([1]).write(to: root.appendingPathComponent("\(i)")) }
        let token = ScanCancellation(); token.cancel()
        XCTAssertTrue(DiskScanner.scan(root, cancellation: token).limited)
        let limited = DiskScanner.scan(root, cancellation: ScanCancellation(), limit: 3)
        XCTAssertTrue(limited.limited)
        XCTAssertEqual(limited.visited, 3)
    }
    func testProtectedHomeCannotBeTrashed() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let item = DiskItem(url: home, size: 0, allocated: 0, directory: true, symlink: false, modified: nil, identity: FileIdentity.read(home), incomplete: false)
        XCTAssertThrowsError(try CleanupSafety.validate(item))
    }
    func testMissingRootIsReported() {
        let result = DiskScanner.scan(URL(fileURLWithPath: "/tmp/nuke-nonexistent-\(UUID())"), cancellation: ScanCancellation())
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.items.isEmpty)
    }
    func testProcessSnapshotParsesCurrentProcess() {
        let processes = ProcessService.list()
        XCTAssertTrue(processes.contains { $0.pid == getpid() })
        XCTAssertTrue(processes.allSatisfy { !$0.started.isEmpty && !$0.command.isEmpty })
    }
    func testCommandTimeoutStopsChild() {
        let start = Date()
        let result = CommandRunner.run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }
}
