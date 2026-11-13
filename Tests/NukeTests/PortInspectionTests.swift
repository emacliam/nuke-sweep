import XCTest
@testable import Nuke

final class PortInspectionTests: XCTestCase {
    func testParsesListeningPortsAndSortsThem() {
        let output = """
        p100
        cnode
        n127.0.0.1:5173
        n[::1]:3000
        p200
        cpython
        n*:8080
        """
        let rows = PortInspection.parse(output)
        XCTAssertEqual(rows.map(\.port), [3000, 5173, 8080])
        XCTAssertEqual(rows.first?.host, "::1")
        XCTAssertEqual(rows.first?.process, "node")
        XCTAssertEqual(rows.last?.process, "python")
        XCTAssertEqual(rows.last?.pid, 200)
    }

    func testRejectsMalformedLinesAndDeduplicates() {
        let output = """
        p300
        cnode
        n127.0.0.1:5173
        n127.0.0.1:5173
        nnot-a-port
        p400
        c
        n*:99999
        """
        let rows = PortInspection.parse(output)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.port, 5173)
        XCTAssertEqual(rows.first?.pid, 300)
    }

    func testInspectReportsPermissionFailureWithoutProcesses() {
        let report = PortInspection.inspect { _, _ in .init(output: "lsof: permission denied", status: 1) }
        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertTrue(report.error?.localizedCaseInsensitiveContains("permission") == true)
    }

    func testInspectAcceptsEmptyOutputAsNoVisiblePorts() {
        let report = PortInspection.inspect { _, _ in .init(output: "", status: 1) }
        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertNotNil(report.error)
    }
}

final class PortFilterTests: XCTestCase {
    func testPortFilterMatchesPortProcessAndAddress() {
        let ports = [
            ListeningPort(pid: 1, process: "node", address: "127.0.0.1:5173", port: 5173),
            ListeningPort(pid: 2, process: "postgres", address: "*:5432", port: 5432)
        ]
        XCTAssertEqual(PortInspection.matching(ports, query: "5173").map(\.pid), [1])
        XCTAssertEqual(PortInspection.matching(ports, query: "postgres").map(\.pid), [2])
        XCTAssertEqual(PortInspection.matching(ports, query: "127.0.0.1").map(\.pid), [1])
        XCTAssertEqual(PortInspection.matching(ports, query: "").count, 2)
        XCTAssertTrue(PortInspection.matching(ports, query: "nope").isEmpty)
    }
}
