import XCTest
@testable import Nuke

final class FastScanTests: XCTestCase {
    private func fixture() throws -> URL {
        // Under the home folder: /var/folders is excluded from FSEvents history on some setups.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fastscan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ url: URL, _ bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    func testDeepAndWideTreesSumExactly() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var expected: Int64 = 0
        for a in 0..<6 { for b in 0..<5 { for c in 0..<4 {
            let size = (a + 1) * 100 + b * 10 + c
            try write(root.appendingPathComponent("a\(a)/b\(b)/c\(c).bin"), size); expected += Int64(size)
        } } }
        try write(root.appendingPathComponent("deep/1/2/3/4/5/6/7/8/leaf.txt"), 4321); expected += 4321
        let result = DiskScanner.scan(root, cancellation: ScanCancellation(), reuse: false)
        XCTAssertEqual(result.logical, expected)
        XCTAssertFalse(result.limited)
        XCTAssertEqual(result.items.first { $0.name == "a5" }?.size, (0..<5).reduce(Int64(0)) { sum, b in sum + (0..<4).reduce(Int64(0)) { $0 + Int64(600 + b * 10 + $1) } })
        XCTAssertEqual(result.categories["Documents"], 4321)
    }

    func testHardLinksCountOnce() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("one/data.bin")
        try write(original, 50_000)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("two"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("two/data.bin"))
        let result = DiskScanner.scan(root, cancellation: ScanCancellation(), reuse: false)
        XCTAssertEqual(result.logical, 50_000)
    }

    func testClonesAreNotCountedAsFreedSpaceTwice() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.bin")
        try write(original, 4_000_000)
        let clone = Process(); clone.executableURL = URL(fileURLWithPath: "/bin/cp")
        clone.arguments = ["-c", original.path, root.appendingPathComponent("clone.bin").path]
        try clone.run(); clone.waitUntilExit()
        try XCTSkipIf(clone.terminationStatus != 0, "this volume cannot clone")
        let result = DiskScanner.scan(root, cancellation: ScanCancellation(), reuse: false)
        XCTAssertEqual(result.logical, 8_000_000, "logical size still counts both names")
        let cloneItem = try XCTUnwrap(result.items.first { $0.name == "clone.bin" })
        XCTAssertLessThan(cloneItem.allocated, 1_000_000, "removing a clone frees almost nothing")
    }

    func testRepeatScanReusesUnchangedFoldersAndSeesChanges() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); ScanMemory.forget() }
        for index in 0..<400 { try write(root.appendingPathComponent("stable/f\(index)"), 10) }
        for index in 0..<400 { try write(root.appendingPathComponent("moving/f\(index)"), 10) }
        let first = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(first.logical, 8000)
        try write(root.appendingPathComponent("moving/new"), 5000)
        let second = DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(second.items.first { $0.name == "moving" }?.size, 9000, "a change made just before the scan is seen")
        XCTAssertEqual(second.items.first { $0.name == "stable" }?.size, 4000)
        XCTAssertEqual(second.logical, 13000)
    }

    func testChildScanReusesParentScanAndSeesChanges() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); ScanMemory.forget() }
        for index in 0..<400 { try write(root.appendingPathComponent("tool/a/f\(index)"), 10) }
        for index in 0..<400 { try write(root.appendingPathComponent("tool/b/f\(index)"), 10) }
        _ = DiskScanner.scan(root, cancellation: ScanCancellation())
        try write(root.appendingPathComponent("tool/b/new"), 777)
        let child = DiskScanner.scan(root.appendingPathComponent("tool"), cancellation: ScanCancellation())
        XCTAssertEqual(child.items.first { $0.name == "a" }?.size, 4000)
        XCTAssertEqual(child.items.first { $0.name == "b" }?.size, 4777, "the change made after the parent scan is seen")
    }
}
