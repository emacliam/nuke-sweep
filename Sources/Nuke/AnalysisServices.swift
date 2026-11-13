import Foundation
import CryptoKit
import Darwin

struct DuplicateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum FileUseService {
    static func inspect(_ url: URL) -> OpenFileReport {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let r = CommandRunner.run("/usr/sbin/lsof", ["-nP", "-Fpcn"] + (isDir ? ["+D", url.path] : ["--", url.path]), timeout: 15)
        let rows = parse(r.output)
        let note: String
        if r.status == 0 { note = "Observed open files only. Permissions and scan timing limit visibility; absence is not proof that an item is unused." }
        else if r.status == 1 && rows.isEmpty && r.output.isEmpty { note = "No open file use was observed with current permissions. This does not prove the item is unused." }
        else { note = "Partial or unavailable open-file inspection (15-second limit). \(r.output.split(separator: "\n").filter { $0.hasPrefix("lsof:") }.prefix(3).joined(separator: "\n"))" }
        return OpenFileReport(uses: Array(rows.prefix(1000)), note: note + (rows.count > 1000 ? " Showing the first 1,000 observations." : ""))
    }
    /// One bounded lsof snapshot used by review to warn about open handles.
    static func snapshot() -> [OpenFileUse] {
        let r = CommandRunner.run("/usr/sbin/lsof", ["-nP", "-Fpcn"], timeout: 8)
        return parse(r.output)
    }
    static func parse(_ text: String) -> [OpenFileUse] {
        var pid: Int32?, name = "", found: [OpenFileUse] = [], seen = Set<String>()
        for line in text.split(separator: "\n") {
            guard let field = line.first else { continue }; let value = String(line.dropFirst())
            if field == "p" { pid = Int32(value); name = "" }
            if field == "c" { name = value }
            if field == "n", let pid { let key = "\(pid):\(value)"; if seen.insert(key).inserted { found.append(.init(pid: pid, process: name, path: value)) } }
        }
        return found
    }
}

enum ProjectDockerService {
    static func inspect() -> (context: String, objects: [ProjectDockerObject], note: String) {
        let c = CommandRunner.run("/usr/bin/env", ["docker", "context", "show"])
        guard c.status == 0 else { return ("", [], "Docker CLI unavailable; filesystem project inventory still works.") }
        let containerFormat = "{\"name\":{{json .Names}},\"project\":{{json (.Label \"com.docker.compose.project\")}},\"directory\":{{json (.Label \"com.docker.compose.project.working_dir\")}},\"state\":{{json .State}}}"
        let volumeFormat = "{\"name\":{{json .Name}},\"project\":{{json (.Label \"com.docker.compose.project\")}}}"
        let container = CommandRunner.run("/usr/bin/env", ["docker", "--context", c.output, "container", "ls", "--all", "--filter", "label=com.docker.compose.project", "--format", containerFormat])
        let volume = CommandRunner.run("/usr/bin/env", ["docker", "--context", c.output, "volume", "ls", "--filter", "label=com.docker.compose.project", "--format", volumeFormat])
        var objects: [ProjectDockerObject] = []
        for (kind, r) in [("Container", container), ("Volume", volume)] where r.status == 0 {
            for line in r.output.split(separator: "\n") {
                guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String], let name = d["name"], let project = d["project"], !project.isEmpty else { continue }
                objects.append(.init(kind: kind, name: name, project: project, directory: d["directory"], state: d["state"] ?? "Persistent data"))
            }
        }
        return (c.output, objects, "Compose labels provide project attribution. Objects without them are unassigned; shared images/build cache are not attributed. Project Docker cleanup is reviewed in Docker, not inferred from filesystem sizes. \(container.status == 0 && volume.status == 0 ? "" : "Some Docker inventory calls failed or timed out. " + [container, volume].filter { $0.status != 0 }.map { String($0.output.prefix(180)) }.joined(separator: " · "))")
    }
}
