import Foundation
import AppKit
import Darwin
import NukeMetrics

/// Streams directory names instead of allocating a URL array for an entire directory.
/// Cancellation is checked before opening and between entries; kernel calls themselves cannot be interrupted.
enum DirectoryEntries {
    @discardableResult static func visit(_ root: URL, shouldContinue: () -> Bool, _ body: (URL) -> Void) throws -> Bool {
        guard shouldContinue() else { return false }
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard let directory = fdopendir(descriptor) else { let code = errno; close(descriptor); throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        defer { closedir(directory) }
        while shouldContinue() {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                return true
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) { String(cString: $0) }
            }
            if name != "." && name != ".." { body(root.appendingPathComponent(name)) }
        }
        return false
    }
}

// lstat prevents following symlinks. Traversal stays on the selected volume.
enum DiskScanner {
    static func scan(_ root: URL, cancellation: ScanCancellation, limit: Int = 250_000, deadline: Date = Date().addingTimeInterval(60), excluding: (URL) -> Bool = { _ in false }, observing: (URL) -> Void = { _ in }) -> ScanResult {
        if excluding(root) { return ScanResult(items: [], skipped: 0, visited: 0, limited: false) }
        var visited = 0, skipped = 0, limited = false
        var categories: [String: Int64] = [:]
        var issues: [ScanAccessIssue] = []
        func recordIssue(_ url: URL, _ reason: String) { if issues.count < 12 { issues.append(.init(path: url.path, reason: reason)) } }
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0 else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false, accessIssues: [.init(path: root.path, reason: String(cString: strerror(errno)))]) }
        guard rootStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false) }
        let device = rootStat.st_dev
        func measure(_ url: URL) -> DiskItem? {
            if excluding(url) { return nil }
            if cancellation.cancelled || visited >= limit || Date() > deadline { limited = true; return nil }
            visited += 1
            observing(url)
            if visited == 1 || visited % 256 == 0 { DiskWork.report(path: url.path, visited: visited) }
            var s = stat()
            guard lstat(url.path, &s) == 0 else { skipped += 1; recordIssue(url, String(cString: strerror(errno))); return nil }
            let mode = s.st_mode & mode_t(S_IFMT)
            let isDir = mode == mode_t(S_IFDIR), link = mode == mode_t(S_IFLNK)
            var logical = isDir ? Int64(0) : Int64(s.st_size)
            var allocated = isDir ? Int64(0) : Int64(s.st_blocks) * 512
            var incomplete = false
            if isDir {
                if s.st_dev != device { skipped += 1; incomplete = true }
                else {
                    do {
                        let complete = try DirectoryEntries.visit(url, shouldContinue: { !cancellation.cancelled && visited < limit && Date() <= deadline }) { child in
                            guard !excluding(child) else { return }
                            if let item = measure(child) { logical += item.size; allocated += item.allocated; incomplete = incomplete || item.incomplete }
                            else { incomplete = true }
                        }
                        if !complete { limited = true; incomplete = true }
                    } catch { skipped += 1; incomplete = true; recordIssue(url, error.localizedDescription) }
                }
            }
            if !isDir && !link { categories[GrowthComparison.category(url), default: 0] += logical }
            return DiskItem(url: url, size: logical, allocated: allocated, directory: isDir, symlink: link, modified: Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec)), identity: FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino)), incomplete: incomplete)
        }
        var items: [DiskItem] = []
        do {
            let complete = try DirectoryEntries.visit(root, shouldContinue: { !cancellation.cancelled && visited < limit && Date() <= deadline }) { child in
                guard !excluding(child) else { return }
                if let item = measure(child) { items.append(item) }
            }
            if !complete { limited = true }
        } catch { skipped += 1; recordIssue(root, error.localizedDescription) }
        return ScanResult(items: items.sorted { $0.size > $1.size }, skipped: skipped, visited: visited, limited: limited, categories: categories, accessIssues: issues)
    }
    static func cache(_ rule: CacheRule, cancellation: ScanCancellation) -> CacheMeasurement {
        guard FileManager.default.fileExists(atPath: rule.url.path) else { return .init(rule: rule, item: nil, skipped: 0) }
        let identity = FileIdentity.read(rule.url)
        let r = scan(rule.url, cancellation: cancellation)
        let item = DiskItem(url: rule.url, size: r.logical, allocated: r.allocated, directory: true, symlink: false, modified: nil, identity: identity, incomplete: r.limited || r.skipped > 0)
        return .init(rule: rule, item: item, skipped: r.skipped)
    }
}
struct CommandResult: Sendable {
    let output: String
    let status: Int32
}
enum CommandRunner {
    private static let lock = NSLock()
    private static var active: [Int32: Process] = [:]
    static func shutdown() {
        lock.lock(); let children = Array(active.values); lock.unlock()
        for child in children where child.isRunning { child.terminate() }
    }
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandResult {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.terminationHandler = { child in lock.lock(); active[child.processIdentifier] = nil; lock.unlock() }
        do { try process.run() } catch { return .init(output: error.localizedDescription, status: -1) }
        lock.lock(); if process.isRunning { active[process.processIdentifier] = process }; lock.unlock()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate(); DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } } } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); deadline.cancel()
        return .init(output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), status: process.terminationStatus)
    }
}
enum ProcessService {
    static func list() -> [ProcessRow] { snapshot().rows }
    static func snapshot() -> (rows: [ProcessRow], error: String?) {
        let r = CommandRunner.run("/bin/ps", ["-axo", "pid=,uid=,%cpu=,rss=,lstart=,comm="])
        guard r.status == 0 else { return ([], "Could not read process information: " + String(r.output.prefix(500))) }
        let rows: [ProcessRow] = r.output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 9, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 10, let pid = Int32(fields[0]), let uid = UInt32(fields[1]), let cpu = Double(fields[2]), let rss = Int64(fields[3]) else { return nil }
            return ProcessRow(pid: pid, cpu: cpu, memory: rss * 1024, command: String(fields[9]), started: fields[4...8].joined(separator: " "), owner: uid)
        }.sorted { $0.cpu > $1.cpu }
        return (rows, rows.isEmpty ? "No process records could be parsed. Refresh to retry; this is not proof that no processes are running." : nil)
    }
}
enum MachineService {
    static func snapshot() -> ResourceSnapshot {
        var r = ResourceSnapshot()
        do {
            let disk = try SystemMetrics.storage()
            r.totalDisk = disk.total; r.freeDisk = disk.free
        } catch { r.error = error.localizedDescription }
        var loads = [Double](repeating: 0, count: 3); getloadavg(&loads, 3); r.load = loads[0]
        return r
    }
}
enum CleanupSafety {
    static func canGrant(_ root: URL) -> Bool {
        let path = root.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return false }
        if path.hasPrefix(home + "/Library/Containers/com.docker.docker/") || path == home + "/Library/Containers/com.docker.docker" { return false }
        if path.hasPrefix(home + "/") { return ![home + "/Library", home + "/.Trash"].contains(path) && !path.hasPrefix(home + "/.Trash/") }
        if path == "/" || root.pathComponents.count < 3 { return false }
        return !["/System", "/Library", "/usr", "/bin", "/sbin", "/dev", "/Users", "/Applications", "/private/etc", "/private/var", "/etc", "/var"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    static func overlapsProtectedTree(_ item: URL, tree: URL) -> Bool {
        let lexical = item.standardizedFileURL.path
        let effective = item.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(item.lastPathComponent).standardizedFileURL.path
        let protected = tree.resolvingSymlinksInPath().standardizedFileURL.path
        return [lexical, effective].contains { $0 == protected || $0.hasPrefix(protected + "/") || protected.hasPrefix($0 + "/") }
    }
    /// Source-control metadata and personal/credential stores are never cleanup targets.
    static func isSensitive(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if [".git", ".hg", ".svn"].contains(name) { return true }
        let trees = [
            home + "/.ssh", home + "/.gnupg", home + "/.aws",
            home + "/Library/Keychains", home + "/Library/Mail", home + "/Library/Messages",
            home + "/Library/Calendars", home + "/Library/AddressBook",
            home + "/Library/Application Support/AddressBook", home + "/Library/Photos",
            home + "/Pictures/Photos Library.photoslibrary"
        ]
        return trees.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func validate(_ item: DiskItem, allowedRoots: [CleanupScope] = []) throws {
        let path = item.url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let resolvedParent = item.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let effectivePath = resolvedParent.appendingPathComponent(item.url.lastPathComponent).standardizedFileURL.path
        let checkedPaths = [path, effectivePath]
        guard !checkedPaths.contains(where: { isSensitive($0) }) else { throw SafetyError.sensitive }
        let protected = [home, home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Pictures", home + "/Movies", home + "/Music", home + "/.Trash"]
        let dockerData = home + "/Library/Containers/com.docker.docker"
        guard !overlapsProtectedTree(item.url, tree: URL(fileURLWithPath: dockerData)) else { throw SafetyError.protectedPath }
        let application = item.url.pathExtension == "app" && path.hasPrefix("/Applications/") && Bundle(url: item.url)?.bundleIdentifier != nil
        let grants = allowedRoots.filter(\.valid).map { $0.root.standardizedFileURL }.filter(canGrant)
        let insideGrant = grants.contains { path.hasPrefix($0.path + "/") }
        guard !item.incomplete, (path.hasPrefix(home + "/") || application || insideGrant), !checkedPaths.contains(where: { protected.contains($0) }), !grants.contains(where: { grant in checkedPaths.contains(grant.path) }), !checkedPaths.contains(where: { $0.hasPrefix(home + "/.Trash/") }), !checkedPaths.contains(where: { let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path; return $0 == bundle || bundle.hasPrefix($0 + "/") }) else { throw SafetyError.protectedPath }
        // The selected item may itself be a symlink; its parent may not escape the allowed scope.
        let parent = resolvedParent.path
        let grantedParent = grants.contains { parent == $0.path || parent.hasPrefix($0.path + "/") }
        guard parent == home || parent.hasPrefix(home + "/") || (application && (parent == "/Applications" || parent.hasPrefix("/Applications/"))) || (insideGrant && grantedParent) else { throw SafetyError.protectedPath }
        guard let identity = item.identity, identity == FileIdentity.read(item.url) else { throw SafetyError.changed }
    }
    enum SafetyError: LocalizedError {
        case protectedPath, sensitive, changed
        var errorDescription: String? {
            switch self {
            case .protectedPath: return "This location is protected, outside a chosen folder, or incompletely measured. Choose a specific folder in Permissions & access, then scan again."
            case .sensitive: return "Nuke Sweep does not clean source-control metadata, credentials, or personal data stores. This item is protected."
            case .changed: return "This item changed since the scan. Scan again before moving it to Trash."
            }
        }
    }
}
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    func stop() { source?.cancel(); source = nil }
    deinit { stop() }
    func start(_ url: URL, onChange: @escaping () -> Void) -> Bool {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        s.setEventHandler(handler: onChange); s.setCancelHandler { close(descriptor) }
        source = s; s.resume(); return true
    }
}
