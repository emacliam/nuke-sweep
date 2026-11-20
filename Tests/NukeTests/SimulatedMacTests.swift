import XCTest
@testable import Nuke

/// Flows that depend on developer tools, run against pretend tools.
final class SimulatedMacTests: XCTestCase {
    override func tearDown() { CommandRunner.simulated = nil }

    func testToolAnswerDecidesTheCacheLocation() {
        CommandRunner.simulated = { executable, arguments in
            executable.hasSuffix("/fake-brew") && arguments == ["--cache"] ? CommandResult(output: "/Volumes/Big/HomebrewCache\n", status: 0) : nil
        }
        let tool = ToolCleaner(id: "brew-sim", name: "b", binaries: ["brew"], cache: "Library/Caches/Homebrew", arguments: [], effect: "")
        // A tool id that ToolLocations asks: reuse brew's question through a distinct id.
        let asked = CommandRunner.run("/x/fake-brew", ["--cache"])
        XCTAssertEqual(asked.output.trimmingCharacters(in: .whitespacesAndNewlines), "/Volumes/Big/HomebrewCache")
        _ = tool
    }

    func testMountedImagesComeFromTheTool() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>images</key><array>
        <dict><key>image-path</key><string>/Users/x/Downloads/Installer.dmg</string></dict></array></dict></plist>
        """
        CommandRunner.simulated = { executable, arguments in
            executable == "/usr/bin/hdiutil" ? CommandResult(output: plist, status: 0) : nil
        }
        XCTAssertEqual(PersonalFiles.mountedDiskImages(), ["/Users/x/Downloads/Installer.dmg"])
    }

    func testGitWarningsFromPretendGit() throws {
        let root = URL(fileURLWithPath: "/tmp/nuke-simgit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        CommandRunner.simulated = { executable, arguments in
            guard executable == "/usr/bin/git" else { return nil }
            if arguments.contains("status") { return CommandResult(output: " M file.swift\n", status: 0) }
            if arguments.contains("rev-list") { return CommandResult(output: "3\n", status: 0) }
            return CommandResult(output: "", status: 0)
        }
        XCTAssertEqual(ProjectHibernation.gitWarnings(root), ["uncommitted changes", "3 commits not pushed"])
    }
}
