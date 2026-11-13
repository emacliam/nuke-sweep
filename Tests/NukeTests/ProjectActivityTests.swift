import XCTest
@testable import Nuke

final class ProjectActivityTests: XCTestCase {
    private func group(_ path: String) -> ProjectGroup {
        ProjectGroup(root: URL(fileURLWithPath: path), kind: "JavaScript / TypeScript", entries: [])
    }

    private func process(_ command: String, pid: Int32 = 42) -> ProcessRow {
        ProcessRow(pid: pid, cpu: 0, memory: 0, command: command, started: "", owner: 501)
    }

    func testMatchesCommandsThatContainProjectRoot() {
        let projects = [group("/Users/example/work/web"), group("/Users/example/work/api")]
        let processes = [
            process("/usr/bin/node /Users/example/work/web/node_modules/vite/bin/vite.js"),
            process("/usr/bin/python /Users/example/work/api/server.py"),
            process("/usr/bin/git status")
        ]
        let active = ProjectActivityDetector.active(projects: projects, processes: processes)
        XCTAssertEqual(active["/Users/example/work/web"], ["node"])
        XCTAssertEqual(active["/Users/example/work/api"], ["python"])
    }

    func testDoesNotMatchPrefixLookalikesOrEmptyInputs() {
        let projects = [group("/Users/example/work/web")]
        let processes = [
            process("/usr/bin/node /Users/example/work/web-other/server.js"),
            process("/usr/bin/node ./server.js")
        ]
        XCTAssertTrue(ProjectActivityDetector.active(projects: projects, processes: processes).isEmpty)
        XCTAssertTrue(ProjectActivityDetector.active(projects: [], processes: processes).isEmpty)
        XCTAssertTrue(ProjectActivityDetector.active(projects: projects, processes: []).isEmpty)
    }

    func testSummaryMentionsActivityAndCapsNames() {
        XCTAssertEqual(ProjectActivityDetector.summary([]), "")
        XCTAssertTrue(ProjectActivityDetector.summary(["node"]).contains("node"))
        XCTAssertTrue(ProjectActivityDetector.summary(["a", "b", "c", "d", "e"]).contains("+1"))
    }
}

final class ProjectPortActivityTests: XCTestCase {
    private func group(_ path: String) -> ProjectGroup {
        ProjectGroup(root: URL(fileURLWithPath: path), kind: "Node", entries: [])
    }

    func testMapsListeningPortsByProcessWorkingDirectory() {
        let projects = [group("/Users/example/work/web"), group("/Users/example/work/api")]
        let ports = [
            ListeningPort(pid: 10, process: "node", address: "127.0.0.1:5173", port: 5173),
            ListeningPort(pid: 20, process: "python", address: "127.0.0.1:8000", port: 8000),
            ListeningPort(pid: 30, process: "postgres", address: "*:5432", port: 5432)
        ]
        let cwd: [Int32: String] = [
            10: "/Users/example/work/web/packages/app",
            20: "/Users/example/work/api",
            30: "/opt/database"
        ]
        let active = ProjectActivityDetector.activeWithPorts(projects: projects, ports: ports, cwd: cwd)
        XCTAssertEqual(active["/Users/example/work/web"], ["node:5173"])
        XCTAssertEqual(active["/Users/example/work/api"], ["python:8000"])
        XCTAssertNil(active["/opt/database"])
    }

    func testPortMappingIgnoresLookalikeDirectoriesAndMissingCWD() {
        let projects = [group("/Users/example/work/web")]
        let ports = [
            ListeningPort(pid: 1, process: "node", address: "*:3000", port: 3000),
            ListeningPort(pid: 2, process: "node", address: "*:3001", port: 3001)
        ]
        let cwd: [Int32: String] = [1: "/Users/example/work/web-other", 2: "/Users/example/work"]
        XCTAssertTrue(ProjectActivityDetector.activeWithPorts(projects: projects, ports: ports, cwd: cwd).isEmpty)
        XCTAssertTrue(ProjectActivityDetector.activeWithPorts(projects: projects, ports: ports, cwd: [:]).isEmpty)
    }

    func testCurrentDirectoryParser() {
        let cwd = PortInspection.currentDirectory(pid: 42) { args, _ in
            XCTAssertTrue(args.contains("-Fn"))
            return .init(output: "p42\nfcwd\nn/Users/example/work/web\n", status: 0)
        }
        XCTAssertEqual(cwd, "/Users/example/work/web")
        XCTAssertNil(PortInspection.currentDirectory(pid: 42) { _, _ in .init(output: "", status: 1) })
    }
}

final class ProjectProcessCWDTests: XCTestCase {
    private func group(_ path: String) -> ProjectGroup {
        ProjectGroup(root: URL(fileURLWithPath: path), kind: "Node", entries: [])
    }

    private func process(_ command: String, pid: Int32) -> ProcessRow {
        ProcessRow(pid: pid, cpu: 0, memory: 0, command: command, started: "", owner: 501)
    }

    func testIdentifiesDevelopmentProcessesAndEnvironmentWrappers() {
        XCTAssertTrue(ProjectActivityDetector.isDevelopmentProcess(process("/usr/bin/node server.js", pid: 1)))
        XCTAssertTrue(ProjectActivityDetector.isDevelopmentProcess(process("/usr/bin/env python3 app.py", pid: 2)))
        XCTAssertFalse(ProjectActivityDetector.isDevelopmentProcess(process("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", pid: 3)))
        XCTAssertEqual(ProjectActivityDetector.executableName("/usr/bin/env node server.js"), "node")
    }

    func testMapsNonListeningDevelopmentProcessesByCWD() {
        let projects = [group("/Users/example/work/web"), group("/Users/example/work/api")]
        let processes = [
            process("/usr/bin/node /Users/example/work/web/dev-server.js", pid: 10),
            process("/usr/bin/env python3 server.py", pid: 20),
            process("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", pid: 30)
        ]
        let cwd: [Int32: String] = [
            10: "/Users/example/work/web",
            20: "/Users/example/work/api",
            30: "/Users/example/work/web"
        ]
        let active = ProjectActivityDetector.activeWithProcessCWD(projects: projects, processes: processes, cwd: cwd)
        XCTAssertEqual(active["/Users/example/work/web"], ["node"])
        XCTAssertEqual(active["/Users/example/work/api"], ["python3"])
        XCTAssertEqual(active.count, 2)
    }

    func testProcessMappingRejectsLookalikesAndMissingCWD() {
        let projects = [group("/Users/example/work/web")]
        let processes = [process("/usr/bin/node server.js", pid: 10)]
        XCTAssertTrue(ProjectActivityDetector.activeWithProcessCWD(projects: projects, processes: processes, cwd: [10: "/Users/example/work/web-other"]).isEmpty)
        XCTAssertTrue(ProjectActivityDetector.activeWithProcessCWD(projects: projects, processes: processes, cwd: [:]).isEmpty)
    }
}
