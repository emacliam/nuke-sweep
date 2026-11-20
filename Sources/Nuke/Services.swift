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
    /// Directories are read with `getattrlistbulk` and walked by every core
    /// from one shared queue (see `ParallelWalk`). Hard links count once, and
    /// sizes on APFS are what removal frees, so clones are not counted twice.
    /// A repeat scan of the same root reuses every subtree FSEvents says is
    /// unchanged. With `observing` or `excluding` set, the walk reads every
    /// entry on one thread, because those callers need to see each one.
    static func scan(_ root: URL, cancellation: ScanCancellation, limit: Int = 2_000_000, deadline: Date = Date().addingTimeInterval(180), excluding: ((URL) -> Bool)? = nil, respectIgnored: Bool = true, observing: ((URL) -> Void)? = nil, visit: (@Sendable (String, BulkEntry) -> Void)? = nil, reuse allowReuse: Bool = true) -> ScanResult {
        let ignored = respectIgnored ? IgnoredLocations.paths : []
        if excluding?(root) == true || IgnoredLocations.contains(root, in: ignored) { return ScanResult(items: [], skipped: 0, visited: 0, limited: false) }
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0 else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false, accessIssues: [.init(path: root.path, reason: String(cString: strerror(errno)))]) }
        guard rootStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return ScanResult(items: [], skipped: 1, visited: 0, limited: false) }
        let device = Int32(rootStat.st_dev)
        let rootPath = root.path
        let plain = observing == nil && excluding == nil
        let memory = plain && visit == nil && allowReuse ? ScanMemory.reuse(for: rootPath, device: rootStat.st_dev, ignored: ignored) : nil
        let walk = ParallelWalk(.init(device: device, limit: limit, deadline: deadline, cancellation: cancellation, ignored: ignored,
                                      excluding: excluding, observing: observing, visit: visit, reuse: memory?.0,
                                      workers: plain ? ProcessInfo.processInfo.activeProcessorCount : 1))
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec)) }
        func identity(_ entry: BulkEntry) -> FileIdentity { FileIdentity(device: UInt64(UInt32(bitPattern: entry.device)), inode: entry.inode) }

        // The root's own children become items; everything below them is totals.
        let rootCategory = FastCategory.forDirectory(rootPath)
        var files: [DiskItem] = []
        var directories: [(url: URL, entry: BulkEntry)] = []
        var rootCategories = [Int64](repeating: 0, count: FastCategory.names.count)
        let fd = open(rootPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            walk.skip(rootPath, String(cString: strerror(errno)))
        } else {
            defer { close(fd) }
            do {
                let complete = try BulkDirectory.read(fd) { entry in
                    if cancellation.cancelled || Date() > deadline { walk.markLimited(); return false }
                    let url = root.appendingPathComponent(entry.name)
                    let path = rootPath + "/" + entry.name
                    if let excluding, excluding(URL(fileURLWithPath: path)) { return true }
                    if !ignored.isEmpty && ignored.contains(path) { return true }
                    guard walk.claim(1) == 1 else { return false }
                    observing?(url)
                    if entry.error != 0 { walk.skip(url.path, String(cString: strerror(entry.error))); return true }
                    visit?(path, entry)
                    if entry.isDirectory {
                        if entry.device != device {
                            walk.skip(nil, nil)
                            files.append(DiskItem(url: url, size: 0, allocated: 0, directory: true, symlink: false, modified: date(entry.modified), accessed: date(entry.accessed), identity: identity(entry), incomplete: true))
                        } else {
                            directories.append((url, entry))
                        }
                        return true
                    }
                    if entry.links > 1 && !entry.isSymlink && !walk.firstLink(entry.inode) { return true }
                    if !entry.isSymlink { rootCategories[FastCategory.forFile(named: entry.name, inherited: rootCategory)] += entry.logical }
                    files.append(DiskItem(url: url, size: entry.logical, allocated: entry.reclaimable, directory: false, symlink: entry.isSymlink, modified: date(entry.modified), accessed: date(entry.accessed), identity: identity(entry), incomplete: false))
                    return true
                }
                if !complete { walk.markLimited() }
            } catch { walk.skip(rootPath, error.localizedDescription) }
        }
        let totals = walk.measure(directories.map { ($0.url.path, rootCategory) })
        let folders = directories.indices.map { index -> DiskItem in
            let (url, entry) = directories[index]
            let value = totals[index]
            return DiskItem(url: url, size: value.logical, allocated: value.allocated, directory: true, symlink: false, modified: date(entry.modified), accessed: date(entry.accessed), identity: identity(entry), incomplete: value.incomplete)
        }
        var categoryTotals = rootCategories
        for value in totals { for index in categoryTotals.indices { categoryTotals[index] += value.categories[index] } }
        var categories: [String: Int64] = [:]
        for (index, name) in FastCategory.names.enumerated() where categoryTotals[index] > 0 { categories[name] = categoryTotals[index] }
        if let memory, !walk.limited, !cancellation.cancelled {
            ScanMemory.remember(rootPath, reuse: memory.0, eventID: memory.1, volume: memory.2, ignored: ignored)
        }
        return ScanResult(items: (files + folders).sorted { $0.size > $1.size }, skipped: walk.skipped, visited: walk.visited, limited: walk.limited, categories: categories, accessIssues: walk.issues)
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
    /// A pretend Mac for tests and demos: when set, every command the app runs
    /// (`simctl`, `brew`, `git`, `hdiutil`, ...) is answered by this instead of
    /// the real tool. Returning nil runs the real one. Never set in a shipping
    /// build. Idea from Major Tom's fake runner (MIT, (c) 2026 Tom Jordan).
    nonisolated(unsafe) static var simulated: (@Sendable (_ executable: String, _ arguments: [String]) -> CommandResult?)?

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15, environment suppliedEnvironment: [String: String]? = nil) -> CommandResult {
        if let simulated, let answer = simulated(executable, arguments) { return answer }
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
    /// Download caches that hold other people's packages, re-fetchable on demand.
    static func isPackageCache(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path) -> Bool {
        let roots = ["/Library/Caches/Yarn/", "/.npm/_cacache/", "/Library/pnpm/store/", "/Library/Caches/CocoaPods/",
                     "/.gradle/caches/", "/Library/Caches/pip/", "/Library/Caches/Homebrew/", "/Library/Caches/org.swift.swiftpm/",
                     "/Library/Caches/go-build/", "/.cargo/registry/", "/.bun/install/cache/", "/.pub-cache/", "/.m2/repository/",
                     "/.cache/uv/", "/Library/Caches/Yarn", "/.npm/_npx/", "/.yarn/berry/cache/", "/.gradle/wrapper/dists/", "/Library/Caches/ms-playwright/", "/Library/Caches/Cypress/"]
        if roots.contains(where: { root in
            let full = home + root
            return path.hasPrefix(full.hasSuffix("/") ? full : full + "/")
        }) { return true }
        // Caches the tools themselves reported, wherever they were moved to.
        return ToolLocations.knownCaches.contains { path.hasPrefix($0 + "/") }
    }
    static func isSensitive(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path) -> Bool {
        // Inside a package manager's download cache, a key-like name is a file
        // some package shipped (React Native templates carry debug.keystore,
        // test suites carry .pem fixtures, git-sourced packages carry .git).
        // It is a copy the tool can fetch again, not the person's secret.
        if isPackageCache(path, home: home) { return false }
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
