import Foundation
import CryptoKit
import Darwin

struct DuplicateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum DuplicateFinder {
    static func digest(_ item: DiskItem, token: ScanCancellation) throws -> String {
        guard item.identity == FileIdentity.read(item.url) else { throw DuplicateFailure(message: "File identity changed.") }
        let before = try item.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let handle = try FileHandle(forReadingFrom: item.url); defer { try? handle.close() }
        var hash = SHA256()
        while true {
            if token.cancelled { throw DuplicateFailure(message: "Cancelled.") }
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }; hash.update(data: data)
        }
        let after = try item.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate, item.identity == FileIdentity.read(item.url) else { throw DuplicateFailure(message: "File changed while hashing.") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func sameContents(_ a: DiskItem, _ b: DiskItem, token: ScanCancellation = ScanCancellation()) throws -> Bool {
        guard a.identity == FileIdentity.read(a.url), b.identity == FileIdentity.read(b.url), a.identity != b.identity else { return false }
        let av = try a.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), bv = try b.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard av.fileSize == bv.fileSize, av.fileSize == Int(a.size), bv.fileSize == Int(b.size) else { return false }
        let ah = try FileHandle(forReadingFrom: a.url), bh = try FileHandle(forReadingFrom: b.url)
        defer { try? ah.close(); try? bh.close() }
        while true {
            if token.cancelled { throw DuplicateFailure(message: "Cancelled.") }
            let x = try ah.read(upToCount: 1_048_576) ?? Data(), y = try bh.read(upToCount: 1_048_576) ?? Data()
            if x != y { return false }; if x.isEmpty { break }
        }
        let endA = try a.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), endB = try b.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return av.fileSize == endA.fileSize && bv.fileSize == endB.fileSize && av.contentModificationDate == endA.contentModificationDate && bv.contentModificationDate == endB.contentModificationDate && a.identity == FileIdentity.read(a.url) && b.identity == FileIdentity.read(b.url)
    }
    static func find(_ root: URL, token: ScanCancellation, limit: Int = 100_000) -> DuplicateReport {
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0, rootStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return .init(groups: [], skipped: 1, limited: false, checked: 0) }
        var buckets: [Int64: [DiskItem]] = [:], skipped = 0, visited = 0, limited = false
        var identities = Set<String>()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else { return .init(groups: [], skipped: 1, limited: false, checked: 0) }
        for case let url as URL in enumerator {
            if token.cancelled || visited >= limit { limited = true; break }; visited += 1
            guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), v.isSymbolicLink != true else { skipped += 1; continue }
            if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current && v.ubiquitousItemDownloadingStatus != .downloaded { skipped += 1; continue }
            guard v.isRegularFile == true, let item = InventoryService.measure(url), item.size > 0, let id = item.identity else { continue }
            let key = "\(id.device):\(id.inode)"
            guard identities.insert(key).inserted else { continue }
            buckets[item.size, default: []].append(item)
        }
        var hashes: [String: [DiskItem]] = [:]
        for items in buckets.values where items.count > 1 {
            for item in items {
                if token.cancelled { limited = true; break }
                do { let hash = try digest(item, token: token); hashes[hash, default: []].append(item) } catch { skipped += 1 }
            }
            if token.cancelled { break }
        }
        var groups: [DuplicateGroup] = []
        for (hash, items) in hashes where items.count > 1 {
            let ordered = items.sorted { $0.url.path < $1.url.path }
            guard let keeper = ordered.first else { continue }
            var confirmed = [keeper]
            for item in ordered.dropFirst() {
                if token.cancelled { limited = true; break }
                if (try? sameContents(keeper, item, token: token)) == true { confirmed.append(item) } else { skipped += 1 }
            }
            if confirmed.count > 1 { groups.append(.init(digest: hash, files: confirmed)) }
        }
        return .init(groups: groups.sorted { $0.extraBytes > $1.extraBytes }, skipped: skipped, limited: limited, checked: visited)
    }
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

enum StartupService {
    static func isMissing(_ executable: String) -> Bool {
        guard executable.hasPrefix("/") else { return false }
        var s = stat()
        if stat(executable, &s) == 0 { return false }
        return errno == ENOENT || errno == ENOTDIR
    }
    static func inspect(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation = ScanCancellation()) -> (entries: [StartupEntry], note: String) {
        guard !token.cancelled else { return ([], "Inspection stopped.") }
        let loaded = CommandRunner.run("/bin/launchctl", ["list"])
        var statuses: [String: String] = [:]
        if loaded.status == 0 {
            for line in loaded.output.split(separator: "\n") {
                let f = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
                if f.count == 3 && f[0] != "PID" { statuses[String(f[2])] = f[0] == "-" ? "Loaded · last exit \(f[1])" : "Running · PID \(f[0])" }
            }
        }
        var entries: [StartupEntry] = [], unreadable = 0
        let roots = [(home.appendingPathComponent("Library/LaunchAgents"), "User agent", true), (URL(fileURLWithPath: "/Library/LaunchAgents"), "System-wide agent", false), (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System daemon", false)]
        for (root, scope, removable) in roots {
            guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for source in files where source.pathExtension == "plist" {
                if token.cancelled { return (entries, "Inspection stopped; results are partial.") }
                guard let data = try? Data(contentsOf: source), let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { unreadable += 1; continue }
                let label = d["Label"] as? String ?? source.deletingPathExtension().lastPathComponent
                let executable = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? d["BundleProgram"] as? String ?? "Unknown"
                var owner = "Owner not established"
                if let range = executable.range(of: ".app/") {
                    let path = String(executable[..<range.lowerBound]) + ".app"
                    owner = Bundle(path: path)?.bundleIdentifier.map { "Bundle: " + $0 } ?? "App path: " + path
                }
                let missing = isMissing(executable)
                let state = statuses[label] ?? (scope == "System daemon" ? "System bootstrap status not queried" : "Not observed in current bootstrap")
                entries.append(.init(source: source, label: label, executable: executable, owner: owner, state: state, scope: scope, missing: missing, canRemove: removable))
            }
        }
        return (entries.sorted { $0.label < $1.label }, "Launch-agent presence is not an enabled-state guarantee. \(unreadable) unreadable plists. \(loaded.status == 0 ? "Loaded state sampled from the current launchctl bootstrap." : "Loaded state unavailable.") Removing a user plist does not unload an already running job.")
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
