import XCTest
@testable import Nuke

/// Suggesting where someone keeps code replaces a folder picker with an answer.
/// It must only suggest places that genuinely look like code, and must never
/// wander outside the home directory it was given.
final class CodeFolderDetectionTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-detect-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeProject(_ container: String, _ name: String, marker: String) throws {
        let directory = home.appendingPathComponent(container).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent(marker))
    }

    func testFindsConventionalFoldersAndCountsProjects() throws {
        try makeProject("Developer", "alpha", marker: "package.json")
        try makeProject("Developer", "beta", marker: "Cargo.toml")
        try makeProject("code", "gamma", marker: "go.mod")

        let found = CodeFolderDetection.detect(home: home)
        let names = found.map(\.name)
        XCTAssertTrue(names.contains("Developer"))
        XCTAssertTrue(names.contains("code"))
        XCTAssertEqual(found.first?.name, "Developer", "The folder with more projects should lead.")
        XCTAssertEqual(found.first?.projectCount, 2)
    }

    func testAFolderWithNoProjectMarkersIsNotSuggested() throws {
        let empty = home.appendingPathComponent("Projects").appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: empty.appendingPathComponent("readme.txt"))

        XCTAssertTrue(CodeFolderDetection.detect(home: home).isEmpty,
                      "A directory of ordinary files is not a projects folder.")
    }

    func testUnconventionalFolderNamesAreIgnored() throws {
        try makeProject("RandomPlaceNobodyUses", "alpha", marker: "package.json")
        XCTAssertTrue(CodeFolderDetection.detect(home: home).isEmpty)
    }

    /// A symlinked candidate could point anywhere; suggesting it would propose
    /// scanning a location outside the home folder.
    func testASymlinkEscapingTheHomeFolderIsNotSuggested() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-outside-" + UUID().uuidString, isDirectory: true)
        let project = outside.appendingPathComponent("alpha")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        defer { try? FileManager.default.removeItem(at: outside) }

        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Developer"),
            withDestinationURL: outside
        )
        XCTAssertTrue(CodeFolderDetection.detect(home: home).isEmpty,
                      "A candidate resolving outside the home folder must not be suggested.")
    }

    func testDetectionIsBoundedByTheChildLimit() throws {
        for index in 0..<40 {
            try makeProject("src", "project-\(index)", marker: "package.json")
        }
        let found = CodeFolderDetection.detect(home: home, limit: 10)
        XCTAssertEqual(found.first?.name, "src")
        XCTAssertLessThanOrEqual(found.first?.projectCount ?? 0, 10, "The limit must cap how much is examined.")
    }

    /// Plenty of people keep code in a folder under Documents that no
    /// conventional name matches.
    func testDeepDetectionFindsACodeFolderInsideDocuments() throws {
        try makeProject("Documents/playground", "alpha", marker: "package.json")
        try makeProject("Documents/playground", "beta", marker: "Package.swift")
        XCTAssertTrue(CodeFolderDetection.detect(home: home).isEmpty, "Documents is only read when asked.")
        let found = CodeFolderDetection.detect(home: home, deep: true)
        XCTAssertEqual(found.first?.name, "playground")
        XCTAssertEqual(found.first?.projectCount, 2)
    }

    func testASingleRepositoryInDocumentsIsNotTreatedAsACodeFolder() throws {
        try makeProject("Documents/notes", "only", marker: "package.json")
        XCTAssertTrue(CodeFolderDetection.detect(home: home, deep: true).isEmpty)
    }

    func testAMissingHomeDirectoryYieldsNoSuggestions() {
        let absent = home.appendingPathComponent("does-not-exist")
        XCTAssertTrue(CodeFolderDetection.detect(home: absent).isEmpty)
    }
}
