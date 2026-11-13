import Foundation

struct ListeningPort: Identifiable, Equatable, Sendable {
    let pid: Int32
    let process: String
    let address: String
    let port: Int

    var id: String { "\(pid):\(port):\(address)" }
    var host: String {
        guard let colon = address.lastIndex(of: ":") else { return address }
        var value = String(address[..<colon])
        if value.hasPrefix("[") && value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        return value.isEmpty ? "*" : value
    }
}

struct PortReport: Sendable {
    let rows: [ListeningPort]
    let error: String?
}

enum PortInspection {
    static func inspect(run: ([String], TimeInterval) -> CommandResult = { CommandRunner.run("/usr/sbin/lsof", $0, timeout: $1) }) -> PortReport {
        let result = run(["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], 8)
        let rows = parse(result.output)
        if result.status != 0, rows.isEmpty {
            let detail = String(result.output.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.localizedCaseInsensitiveContains("permission") {
                return PortReport(rows: [], error: "Port inspection was partially denied by permissions. Run with broader access or use Activity Monitor; no process was started.")
            }
            return PortReport(rows: [], error: "No listening TCP ports were returned. This is not proof that no process is listening; permissions may hide it.")
        }
        return PortReport(rows: rows, error: nil)
    }

    static func currentDirectory(pid: Int32, run: ([String], TimeInterval) -> CommandResult = { CommandRunner.run("/usr/sbin/lsof", $0, timeout: $1) }) -> String? {
        let result = run(["-a", "-p", String(pid), "-d", "cwd", "-Fn"], 3)
        guard result.status == 0 else { return nil }
        for line in result.output.split(separator: "\n") where line.first == "n" {
            let value = String(line.dropFirst())
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func parse(_ text: String) -> [ListeningPort] {
        var pid: Int32?
        var process = ""
        var rows: [ListeningPort] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())
            switch first {
            case "p": pid = Int32(value)
            case "c": process = value
            case "n":
                guard let pid, !process.isEmpty, let port = portNumber(from: value) else { continue }
                let row = ListeningPort(pid: pid, process: process, address: value, port: port)
                if seen.insert(row.id).inserted { rows.append(row) }
            default: continue
            }
        }
        return rows.sorted { lhs, rhs in
            lhs.port == rhs.port ? lhs.process.localizedStandardCompare(rhs.process) == .orderedAscending : lhs.port < rhs.port
        }
    }

    static func matching(_ ports: [ListeningPort], query: String) -> [ListeningPort] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ports }
        return ports.filter { port in
            String(port.port).contains(trimmed)
                || port.process.localizedCaseInsensitiveContains(trimmed)
                || port.address.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private static func portNumber(from address: String) -> Int? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        let value = address[address.index(after: colon)...]
        guard let port = Int(value), (1...65_535).contains(port) else { return nil }
        return port
    }
}
