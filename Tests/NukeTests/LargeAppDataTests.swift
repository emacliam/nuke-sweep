import XCTest
@testable import Nuke

final class LargeAppDataTests: XCTestCase {
    func testReportMeasuresDefaultLocationsAndSkipsSymlinkedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let steam = root.appendingPathComponent("Library/Application Support/Steam/steamapps")
        try FileManager.default.createDirectory(at: steam, withIntermediateDirectories: true)
        try Data(repeating: 42, count: 8192).write(to: steam.appendingPathComponent("game.bin"))
        let messages = root.appendingPathComponent("Library/Messages")
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: messages.appendingPathComponent("Attachments"), withDestinationURL: steam)

        let results = LargeAppData.inspect(home: root)
        let measured = try XCTUnwrap(results.first { $0.name == "Steam" })
        XCTAssertGreaterThanOrEqual(measured.bytes ?? 0, 8192)
        XCTAssertFalse(measured.partial)
        let skipped = try XCTUnwrap(results.first { $0.name == "Messages" })
        XCTAssertNil(skipped.bytes)
        XCTAssertTrue(skipped.partial)
    }
}
