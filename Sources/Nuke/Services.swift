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
    /// Measures everything under `root` without following symlinks or leaving
    /// its volume.
    ///
    /// Each directory is read with `getattrlistbulk`, so sizes and identities
    /// for a whole batch of entries arrive in one call, and separate subtrees
    /// are measured in parallel near the top of the tree. With `observing` set,
    /// the walk stays on one thread, because observers keep their own state.
    static func scan(_ root: URL, cancellation: ScanCancellation, limit: Int = 2_000_000, deadline: Date = Date().addingTimeInterval(180), excluding: ((URL) -> Bool)? = nil, respectIgnored: Bool = true, observing: ((URL) -> Void)? = nil) -> ScanResult {
        let ignored = respectIgnored ? IgnoredLocations.paths : []
        if excluding?(root) == true || IgnoredLocations.contains(root, in: ignored) { return ScanResult(items: [], skipped: 0, visited: 0, limited: false) }
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0 else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false, accessIssues: [.init(path: root.path, reason: String(cString: strerror(errno)))]) }
        guard rootStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false) }
        let device = Int32(rootStat.st_dev)
        let tally = ScanTally(limit: limit)
        let report = DiskWork.reporter()
        let parallel = observing == nil
        let checkIgnored = !ignored.isEmpty

        func stopping() -> Bool { cancellation.cancelled || Date() > deadline }
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec)) }

        /// Admits one entry: exclusions, ignored locations, the budget and the
        /// observer. Nil means skip it silently; false means count it as missing.
        func admit(_ path: String, seen: inout Int) -> Bool? {
            if let excluding, excluding(URL(fileURLWithPath: path)) { return nil }
            if checkIgnored && ignored.contains(path) { return false }
            guard tally.take() else { return false }
            seen += 1
            observing?(URL(fileURLWithPath: path))
            if seen % 256 == 1 { report?(path, tally.visited) }
            return true
        }

        /// Totals for one directory's subtree: logical, allocated, incomplete.
        func walk(_ path: String, inherited: String?, depth: Int) -> (Int64, Int64, Bool) {
            if stopping() { tally.markLimited(); return (0, 0, true) }
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { tally.skip(path, String(cString: strerror(errno))); return (0, 0, true) }
            defer { close(fd) }
            let category = FastCategory.forDirectory(path) ?? inherited
            var logical: Int64 = 0, allocated: Int64 = 0, incomplete = false, seen = 0
            var local: [String: Int64] = [:]
            var subdirectories: [String] = []
            do {
                let complete = try BulkDirectory.read(fd) { entry in
                    if seen % 512 == 511 && stopping() { tally.markLimited(); return false }
                    let child = path + "/" + entry.name
                    guard let admitted = admit(child, seen: &seen) else { return true }
                    guard admitted else { incomplete = true; return !tally.limited }
                    if entry.error != 0 { tally.skip(child, String(cString: strerror(entry.error))); incomplete = true; return true }
                    if entry.isDirectory {
                        if entry.device != device { tally.skip(nil, nil); incomplete = true } else { subdirectories.append(child) }
                    } else {
                        logical += entry.logical; allocated += entry.allocated
                        if !entry.isSymlink { local[FastCategory.forFile(named: entry.name, inherited: category), default: 0] += entry.logical }
                    }
                    return true
                }
                if !complete { incomplete = true }
            } catch { tally.skip(path, error.localizedDescription); incomplete = true }
            tally.merge(local)
            let totals = measure(subdirectories, inherited: category, depth: depth + 1)
            return (logical + totals.0, allocated + totals.1, incomplete || totals.2)
        }

        func measure(_ directories: [String], inherited: String?, depth: Int) -> (Int64, Int64, Bool) {
            if parallel && depth <= 2 && directories.count > 1 {
                let results = UnsafeMutableBufferPointer<(Int64, Int64, Bool)>.allocate(capacity: directories.count)
                defer { results.deallocate() }
                DispatchQueue.concurrentPerform(iterations: directories.count) { index in
                    results[index] = walk(directories[index], inherited: inherited, depth: depth)
                }
                return results.reduce((0, 0, false)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 || $1.2) }
            }
            return directories.reduce((0, 0, false)) { sum, directory in
                let value = walk(directory, inherited: inherited, depth: depth)
                return (sum.0 + value.0, sum.1 + value.1, sum.2 || value.2)
            }
        }

        // The root's own children become items; everything below is totals.
        let rootPath = root.path
        let rootCategory = FastCategory.forDirectory(rootPath)
        var files: [DiskItem] = []
        var directories: [(url: URL, entry: BulkEntry)] = []
        var seen = 0
        let fd = open(rootPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            tally.skip(rootPath, String(cString: strerror(errno)))
        } else {
            defer { close(fd) }
            do {
                var rootLocal: [String: Int64] = [:]
                let complete = try BulkDirectory.read(fd) { entry in
                    if stopping() { tally.markLimited(); return false }
                    let url = root.appendingPathComponent(entry.name)
                    guard let admitted = admit(rootPath + "/" + entry.name, seen: &seen) else { return true }
                    guard admitted else { return !tally.limited }
                    if entry.error != 0 { tally.skip(url.path, String(cString: strerror(entry.error))); return true }
                    let identity = FileIdentity(device: UInt64(UInt32(bitPattern: entry.device)), inode: entry.inode)
                    if entry.isDirectory {
                        directories.append((url, entry))
                    } else {
                        if !entry.isSymlink { rootLocal[FastCategory.forFile(named: entry.name, inherited: rootCategory), default: 0] += entry.logical }
                        files.append(DiskItem(url: url, size: entry.logical, allocated: entry.allocated, directory: false, symlink: entry.isSymlink, modified: date(entry.modified), accessed: date(entry.accessed), identity: identity, incomplete: false))
                    }
                    return true
                }
                if !complete { tally.markLimited() }
                tally.merge(rootLocal)
            } catch { tally.skip(rootPath, error.localizedDescription) }
        }
        let measured = UnsafeMutableBufferPointer<(Int64, Int64, Bool)>.allocate(capacity: max(1, directories.count))
        defer { measured.deallocate() }
        func measureTop(_ index: Int) {
            let (url, entry) = directories[index]
            if entry.device != device { tally.skip(nil, nil); measured[index] = (0, 0, true); return }
            measured[index] = walk(url.path, inherited: rootCategory, depth: 1)
        }
        if parallel && directories.count > 1 {
            DispatchQueue.concurrentPerform(iterations: directories.count, execute: measureTop)
        } else {
            for index in directories.indices { measureTop(index) }
        }
        let folders = directories.indices.map { index -> DiskItem in
            let (url, entry) = directories[index]
            let totals = measured[index]
            return DiskItem(url: url, size: totals.0, allocated: totals.1, directory: true, symlink: false, modified: date(entry.modified), accessed: date(entry.accessed), identity: FileIdentity(device: UInt64(UInt32(bitPattern: entry.device)), inode: entry.inode), incomplete: totals.2)
        }
        return ScanResult(items: (files + folders).sorted { $0.size > $1.size }, skipped: tally.skipped, visited: tally.visited, limited: tally.limited, categories: tally.categories, accessIssues: tally.issues)
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
    // Guarded by `lock`; see DiskWork for the same pattern.
    nonisolated(unsafe) private static var active: [Int32: Process] = [:]
    static func shutdown() {
        lock.lock(); let children = Array(active.values); lock.unlock()
        for child in children where child.isRunning { child.terminate() }
    }
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15, environment suppliedEnvironment: [String: String]? = nil) -> CommandResult {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        var environment = suppliedEnvironment ?? ProcessInfo.processInfo.environment
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
        let components = Set(URL(fileURLWithPath: path).pathComponents.map { $0.lowercased() })
        if !components.isDisjoint(with: [".git", ".hg", ".svn", ".ssh", ".gnupg", ".aws"]) { return true }
        let examples = [".example", ".sample", ".template"]
        if (name == ".env" || name.hasPrefix(".env.")) && !examples.contains(where: { name.hasSuffix($0) }) { return true }
        if [".npmrc", ".pypirc", ".netrc", "credentials.json", "service-account.json"].contains(name) { return true }
        if ["pem", "key", "p12", "pfx", "jks", "keystore"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { return true }
        let trees = [
            home + "/.ssh", home + "/.gnupg", home + "/.aws",
            home + "/Library/Keychains", home + "/Library/Mail", home + "/Library/Messages",
            home + "/Library/Calendars", home + "/Library/AddressBook",
            home + "/Library/Application Support/AddressBook", home + "/Library/Photos",
            home + "/Pictures/Photos Library.photoslibrary"
        ]
        return trees.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func validate(_ item: DiskItem, allowedRoots: [CleanupScope] = [], developerScopes: [DeveloperScope] = []) throws {
        let path = item.url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let resolvedParent = item.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let effectivePath = resolvedParent.appendingPathComponent(item.url.lastPathComponent).standardizedFileURL.path
        let checkedPaths = [path, effectivePath]
        let ignored = IgnoredLocations.paths
        guard !checkedPaths.contains(where: { IgnoredLocations.overlaps(URL(fileURLWithPath: $0), in: ignored) }) else {
            throw SafetyError.developerScope("This item is ignored or contains an ignored location.")
        }
        for candidate in Set(checkedPaths) {
            if let reason = DeveloperScope.cleanupBlock(for: candidate, in: developerScopes, resolvingRoots: true) {
                throw SafetyError.developerScope(reason)
            }
        }
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
        case developerScope(String)
        var errorDescription: String? {
            switch self {
            case .protectedPath: return "This location is protected, outside a chosen folder, or incompletely measured. Choose a specific folder in Permissions & access, then scan again."
            case .sensitive: return "Nuke Sweep does not clean source-control metadata, credentials, or personal data stores. This item is protected."
            case .developerScope(let reason): return reason
            case .changed: return "This item changed since the scan. Scan again before moving it to Trash."
            }
        }
    }
}
