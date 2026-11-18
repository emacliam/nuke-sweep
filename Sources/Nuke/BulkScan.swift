import CoreServices
import Darwin
import Foundation

/// One directory entry as `getattrlistbulk` returns it.
///
/// One system call fills a buffer with the name, type, sizes, identity and times
/// of many entries at once. The per-file `lstat` it replaces was most of the cost
/// of a scan: a folder of 10,000 files was 10,000 calls, and is now a handful.
struct BulkEntry {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var device: Int32
    var inode: UInt64
    var links: UInt32
    var logical: Int64
    var allocated: Int64
    /// Space only this file holds. On APFS a clone shares its blocks with the
    /// original, so this is what removing it actually frees. Nil when the
    /// filesystem does not report it.
    var privateSize: Int64?
    var modified: timespec
    var accessed: timespec
    var error: Int32

    /// What removing this file returns to the disk.
    var reclaimable: Int64 { privateSize.map { min($0, allocated) } ?? allocated }
}

enum BulkDirectory {
    private static let bufferSize = 256 * 1024

    /// Reads every entry of the open directory `fd`. `body` returns false to stop.
    /// Returns false when stopped early. Throws the errno of a failed read.
    static func read(_ fd: Int32, _ body: (BulkEntry) -> Bool) throws -> Bool {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(bitPattern: ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_ACCTIME) | attrgroup_t(ATTR_CMN_FILEID)
        list.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_DATALENGTH) | attrgroup_t(ATTR_FILE_DATAALLOCSIZE)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        let options = UInt64(FSOPT_ATTR_CMN_EXTENDED)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let count = getattrlistbulk(fd, &list, buffer, bufferSize, options)
            if count < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if count == 0 { return true }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if !body(parse(entry)) { return false }
                entry += length
            }
        }
    }

    private static func parse(_ start: UnsafeMutableRawPointer) -> BulkEntry {
        var cursor = start + MemoryLayout<UInt32>.size
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size
        var result = BulkEntry(name: "", isDirectory: false, isSymlink: false, device: 0, inode: 0, links: 1,
                               logical: 0, allocated: 0, privateSize: nil, modified: timespec(), accessed: timespec(), error: 0)
        let common = returned.commonattr
        if common & attrgroup_t(bitPattern: ATTR_CMN_ERROR) != 0 {
            result.error = Int32(bitPattern: cursor.loadUnaligned(as: UInt32.self)); cursor += 4
        }
        if common & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let reference = cursor.loadUnaligned(as: attrreference_t.self)
            result.name = String(cString: (cursor + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
            cursor += MemoryLayout<attrreference_t>.size
        }
        if common & attrgroup_t(ATTR_CMN_DEVID) != 0 { result.device = cursor.loadUnaligned(as: Int32.self); cursor += 4 }
        if common & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            let type = cursor.loadUnaligned(as: UInt32.self); cursor += 4
            result.isDirectory = type == VDIR.rawValue
            result.isSymlink = type == VLNK.rawValue
        }
        if common & attrgroup_t(ATTR_CMN_MODTIME) != 0 { result.modified = cursor.loadUnaligned(as: timespec.self); cursor += MemoryLayout<timespec>.size }
        if common & attrgroup_t(ATTR_CMN_ACCTIME) != 0 { result.accessed = cursor.loadUnaligned(as: timespec.self); cursor += MemoryLayout<timespec>.size }
        if common & attrgroup_t(ATTR_CMN_FILEID) != 0 { result.inode = cursor.loadUnaligned(as: UInt64.self); cursor += 8 }
        let file = returned.fileattr
        if file & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 { result.links = cursor.loadUnaligned(as: UInt32.self); cursor += 4 }
        if file & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 { result.logical = cursor.loadUnaligned(as: Int64.self); cursor += 8 }
        if file & attrgroup_t(ATTR_FILE_DATAALLOCSIZE) != 0 { result.allocated = cursor.loadUnaligned(as: Int64.self); cursor += 8 }
        if returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 { result.privateSize = cursor.loadUnaligned(as: Int64.self) }
        return result
    }
}

/// The file categories `GrowthComparison.category` names, as fixed slots so a
/// subtree's breakdown is eight integers rather than a dictionary.
enum FastCategory {
    static let names = ["Developer artifacts", "Caches", "AI models and caches", "Images", "Video and audio",
                        "Archives and installers", "Documents", "Other files"]

    static func forDirectory(_ path: String) -> Int? {
        let lower = (path + "/").lowercased()
        if lower.contains("/node_modules/") || lower.contains("/deriveddata/") || lower.contains("/target/") || lower.contains("/.next/") { return 0 }
        if lower.contains("/caches/") || lower.contains("/.cache/") || lower.contains("/.npm/") { return 1 }
        if lower.contains("/.ollama/") || lower.contains("/.lmstudio/") || lower.contains("/huggingface/") { return 2 }
        return nil
    }
    static func forFile(named name: String, inherited: Int?) -> Int {
        if let inherited { return inherited }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return 7 }
        switch name[name.index(after: dot)...].lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "raw": return 3
        case "mov", "mp4", "mkv", "mp3", "wav", "m4a": return 4
        case "zip", "dmg", "pkg", "tar", "gz", "ipa": return 5
        case "pdf", "docx", "txt", "md", "xlsx", "pages": return 6
        default: return 7
        }
    }
}

/// Totals for one directory's subtree. Also what the scan cache stores.
struct SubtreeTotals: Codable, Sendable {
    var logical: Int64 = 0
    var allocated: Int64 = 0
    var entries: Int = 0
    var incomplete = false
    var categories = [Int64](repeating: 0, count: FastCategory.names.count)

    mutating func add(_ other: SubtreeTotals) {
        logical += other.logical; allocated += other.allocated; entries += other.entries
        incomplete = incomplete || other.incomplete
        for index in categories.indices { categories[index] += other.categories[index] }
    }
}

/// A directory waiting to be read, or read and waiting for its children.
private final class WalkNode {
    let path: String
    let parent: Int
    let depth: Int
    let inherited: Int?
    var own = SubtreeTotals()
    var cached = false
    var index = -1
    init(path: String, parent: Int, depth: Int, inherited: Int?) {
        self.path = path; self.parent = parent; self.depth = depth; self.inherited = inherited
    }
}

/// Walks a tree with every core: one shared stack of directories still to read,
/// and any idle worker takes the next one. A single enormous folder no longer
/// leaves the other cores finished and waiting, as a fixed split by top-level
/// folder did.
final class ParallelWalk: @unchecked Sendable {
    struct Options {
        var device: Int32
        var limit: Int
        var deadline: Date
        var cancellation: ScanCancellation
        var ignored: Set<String>
        var excluding: ((URL) -> Bool)?
        var observing: ((URL) -> Void)?
        var reuse: ScanReuse?
        var workers: Int
    }

    private let options: Options
    private let condition = NSCondition()
    private var nodes: [WalkNode] = []
    private var stack: [Int] = []
    private var busy = 0
    private var budgetUsed = 0
    private(set) var limited = false
    private(set) var skipped = 0
    private(set) var issues: [ScanAccessIssue] = []
    private var seenLinks = Set<UInt64>()
    private let report: (@Sendable (String, Int) -> Void)?

    init(_ options: Options) {
        self.options = options
        report = DiskWork.reporter()
    }

    var visited: Int { condition.lock(); defer { condition.unlock() }; return budgetUsed }

    /// Measures each directory in `roots` (absolute paths) and returns their totals in order.
    func measure(_ roots: [(path: String, inherited: Int?)]) -> [SubtreeTotals] {
        condition.lock()
        for (index, root) in roots.enumerated() {
            let node = WalkNode(path: root.path, parent: -1, depth: 0, inherited: root.inherited)
            node.index = index
            nodes.append(node)
            stack.append(index)
        }
        condition.unlock()
        let workers = max(1, options.workers)
        if workers == 1 { work() } else { DispatchQueue.concurrentPerform(iterations: workers) { _ in work() } }
        // Children were appended after their parents, so a reverse pass sums
        // every subtree bottom-up in one sweep.
        var totals = nodes.map(\.own)
        for index in nodes.indices.reversed() where nodes[index].parent >= 0 {
            totals[nodes[index].parent].add(totals[index])
        }
        if let reuse = options.reuse {
            for (index, node) in nodes.enumerated() where !node.cached { reuse.store(node.path, totals[index]) }
        }
        return Array(totals.prefix(roots.count))
    }

    private func stopping() -> Bool { options.cancellation.cancelled || Date() > options.deadline }

    private func work() {
        while true {
            condition.lock()
            while stack.isEmpty && busy > 0 { condition.wait() }
            guard let index = stack.popLast() else { condition.broadcast(); condition.unlock(); return }
            busy += 1
            let node = nodes[index]
            condition.unlock()
            let children = read(node)
            condition.lock()
            for child in children {
                child.index = nodes.count
                nodes.append(child)
                stack.append(child.index)
            }
            busy -= 1
            // Wake waiting workers only when there is new work, or when the
            // walk is over; waking all of them after every folder made them
            // queue on the lock for nothing.
            if children.count == 1 { condition.signal() }
            else if children.count > 1 || (busy == 0 && stack.isEmpty) { condition.broadcast() }
            condition.unlock()
        }
    }

    /// Claims `count` entries against the budget; returns how many were granted.
    func claim(_ count: Int, at path: String? = nil) -> Int {
        condition.lock()
        let before = budgetUsed
        let granted = max(0, min(count, options.limit - budgetUsed))
        budgetUsed += granted
        if granted < count { limited = true }
        let total = budgetUsed
        condition.unlock()
        // Progress every 4,096 entries: per-entry reporting took two locks per
        // file and kept the workers waiting on each other.
        if let report, let path, before / 4096 != total / 4096 { report(path, total) }
        return granted
    }
    func skip(_ path: String?, _ reason: String?) {
        condition.lock(); defer { condition.unlock() }
        skipped += 1
        if let path, let reason, issues.count < 12 { issues.append(.init(path: path, reason: reason)) }
    }
    func markLimited() { condition.lock(); limited = true; condition.unlock() }
    /// True the first time a hard-linked inode is seen; later names count nothing.
    func firstLink(_ inode: UInt64) -> Bool {
        condition.lock(); defer { condition.unlock() }
        return seenLinks.insert(inode).inserted
    }

    private func read(_ node: WalkNode) -> [WalkNode] {
        if stopping() { markLimited(); node.own.incomplete = true; return [] }
        // Unchanged since the last scan: take the remembered totals and skip the subtree.
        if let reuse = options.reuse, let remembered = reuse.unchanged(node.path) {
            let granted = claim(remembered.entries)
            if granted == remembered.entries { node.own = remembered; node.cached = true; return [] }
        }
        let fd = open(node.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { skip(node.path, String(cString: strerror(errno))); node.own.incomplete = true; return [] }
        defer { close(fd) }
        let category = FastCategory.forDirectory(node.path) ?? node.inherited
        var totals = SubtreeTotals()
        var children: [WalkNode] = []
        var pending: [BulkEntry] = []
        var stopped = false
        func flush() {
            guard !pending.isEmpty else { return }
            let granted = claim(pending.count, at: node.path)
            for entry in pending.prefix(granted) { account(entry, node: node, category: category, totals: &totals, children: &children) }
            if granted < pending.count { totals.incomplete = true; stopped = true }
            totals.entries += granted
            pending.removeAll(keepingCapacity: true)
        }
        do {
            let complete = try BulkDirectory.read(fd) { entry in
                let child = node.path + "/" + entry.name
                if let excluding = options.excluding, excluding(URL(fileURLWithPath: child)) { return true }
                if !options.ignored.isEmpty && options.ignored.contains(child) { totals.incomplete = true; return true }
                pending.append(entry)
                if pending.count >= 128 {
                    flush()
                    if stopped { return false }
                    if stopping() { markLimited(); totals.incomplete = true; return false }
                }
                return true
            }
            flush()
            if !complete { totals.incomplete = true }
        } catch { skip(node.path, error.localizedDescription); totals.incomplete = true }
        node.own = totals
        return children
    }

    private func account(_ entry: BulkEntry, node: WalkNode, category: Int?, totals: inout SubtreeTotals, children: inout [WalkNode]) {
        let child = node.path + "/" + entry.name
        if let observing = options.observing { observing(URL(fileURLWithPath: child)) }
        if entry.error != 0 { skip(child, String(cString: strerror(entry.error))); totals.incomplete = true; return }
        if entry.isDirectory {
            if entry.device != options.device { skip(nil, nil); totals.incomplete = true; return }
            children.append(WalkNode(path: child, parent: node.index, depth: node.depth + 1, inherited: category))
            return
        }
        if entry.links > 1 && !entry.isSymlink && !firstLink(entry.inode) { return }
        totals.logical += entry.logical
        totals.allocated += entry.reclaimable
        if !entry.isSymlink { totals.categories[FastCategory.forFile(named: entry.name, inherited: category)] += entry.logical }
    }
}

/// Remembered subtree totals for one scan root, and the FSEvents position they
/// are valid at. A later scan of the same root asks macOS which folders changed
/// since then and reads only those; every other subtree comes from memory.
final class ScanReuse: @unchecked Sendable {
    private let remembered: [String: SubtreeTotals]
    private let changed: [String]
    private var lock = os_unfair_lock()
    private var fresh: [String: SubtreeTotals] = [:]
    /// Subtrees smaller than this are cheaper to read again than to remember.
    static let minimumEntries = 256

    init(remembered: [String: SubtreeTotals], changed: [String]) {
        self.remembered = remembered
        self.changed = changed.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }.sorted()
    }

    /// The remembered totals for `path`, if nothing at or below it has changed.
    func unchanged(_ path: String) -> SubtreeTotals? {
        guard let totals = remembered[path] else { return nil }
        return dirty(path) ? nil : totals
    }

    private func dirty(_ path: String) -> Bool {
        let prefix = path + "/"
        var low = 0, high = changed.count
        while low < high { let mid = (low + high) / 2; if changed[mid] < path { low = mid + 1 } else { high = mid } }
        // Everything starting with `path` sorts together from here, including
        // siblings such as "path-2", which are skipped.
        var index = low
        while index < changed.count, changed[index].hasPrefix(path) {
            if changed[index] == path || changed[index].hasPrefix(prefix) { return true }
            index += 1
        }
        return false
    }

    func store(_ path: String, _ totals: SubtreeTotals) {
        guard totals.entries >= Self.minimumEntries, !totals.incomplete else { return }
        os_unfair_lock_lock(&lock); fresh[path] = totals; os_unfair_lock_unlock(&lock)
    }

    /// What to remember after this scan: everything re-measured, plus whatever
    /// was reused unchanged.
    func result() -> [String: SubtreeTotals] {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        var merged = fresh
        for (path, totals) in remembered where merged[path] == nil && !dirty(path) { merged[path] = totals }
        return merged
    }
}

/// Persistent scan memory, keyed by scan root.
enum ScanMemory {
    struct Snapshot: Codable {
        var eventID: UInt64
        var volume: String
        var ignored: [String]
        var used: Date
        var totals: [String: SubtreeTotals]
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: [String: Snapshot]?
    private static let maxRoots = 24
    private static let maxEntries = 400_000
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppEnvironment.supportName + "/scan-memory.plist")
    }

    private static func all() -> [String: Snapshot] {
        if let loaded { return loaded }
        let decoded = (try? Data(contentsOf: url)).flatMap { try? PropertyListDecoder().decode([String: Snapshot].self, from: $0) } ?? [:]
        loaded = decoded
        return decoded
    }

    /// A reuse plan for scanning `root`, or nil when nothing trustworthy is remembered.
    static func reuse(for root: String, device: dev_t, ignored: Set<String>) -> (ScanReuse, UInt64, String)? {
        let now = FSEventsGetCurrentEventId()
        let volume = (FSEventsCopyUUIDForDevice(device)).map { CFUUIDCreateString(nil, $0) as String } ?? ""
        lock.lock(); let snapshot = all()[root]; lock.unlock()
        guard let snapshot, !volume.isEmpty, snapshot.volume == volume, Set(snapshot.ignored) == ignored,
              snapshot.eventID <= now, let changed = FSEventsHistory.changes(since: snapshot.eventID, under: canonical(root)) else {
            return (ScanReuse(remembered: [:], changed: []), now, volume)
        }
        // FSEvents reports resolved paths (/private/var/…); scans may use the
        // symlinked spelling (/var/…). Map events back to the scan's spelling.
        let real = canonical(root)
        let mapped = real == root ? changed : changed.map { $0.hasPrefix(real) ? root + $0.dropFirst(real.count) : $0 }
        return (ScanReuse(remembered: snapshot.totals, changed: mapped), now, volume)
    }

    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func remember(_ root: String, reuse: ScanReuse, eventID: UInt64, volume: String, ignored: Set<String>) {
        guard !volume.isEmpty else { return }
        let totals = reuse.result()
        lock.lock()
        var snapshots = all()
        snapshots[root] = Snapshot(eventID: eventID, volume: volume, ignored: Array(ignored), used: Date(), totals: totals)
        // Keep the most recently used roots within the entry budget.
        var kept: [String: Snapshot] = [:], count = 0
        for (key, value) in snapshots.sorted(by: { $0.value.used > $1.value.used }) where kept.count < maxRoots && count + value.totals.count <= maxEntries {
            kept[key] = value; count += value.totals.count
        }
        loaded = kept
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            lock.lock(); let snapshot = loaded ?? [:]; lock.unlock()
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            guard let data = try? encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    static func forget() {
        lock.lock(); loaded = [:]; lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }
}

/// Asks FSEvents which folders under a path changed since an event ID.
///
/// Replaying history alone is not enough: a change made a moment ago may not
/// have reached the event log yet, and a scan that missed it would reuse a stale
/// size. So after the replay, the query touches a marker file of its own and
/// waits until FSEvents reports it. Events arrive in order, so every change made
/// before the marker has been delivered by then.
enum FSEventsHistory {
    private final class Collector: @unchecked Sendable {
        var paths: [String] = []
        var trustworthy = true
        var replayed = false
        var markerSeen = false
        var markerPrefix = ""
        let replay = DispatchSemaphore(value: 0)
        let marker = DispatchSemaphore(value: 0)
    }

    static var markerDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppEnvironment.supportName + "/fsevents-marker", isDirectory: true)
    }

    /// Nil when the history cannot be trusted: dropped, wrapped, or not confirmed in time.
    static func changes(since eventID: UInt64, under root: String, timeout: TimeInterval = 3) -> [String]? {
        let markerDirectory = Self.markerDirectory
        try? FileManager.default.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        guard let resolvedMarker = realpath(markerDirectory.path, nil) else { return nil }
        let markerPath = String(cString: resolvedMarker); free(resolvedMarker)
        let collector = Collector()
        collector.markerPrefix = markerPath
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(collector).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let collector = Unmanaged<Collector>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self)
            let untrusted = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount)
            for index in 0..<count {
                let flag = flags[index]
                if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 {
                    if !collector.replayed { collector.replayed = true; collector.replay.signal() }
                    continue
                }
                if flag & untrusted != 0 { collector.trustworthy = false }
                guard let path = list[index] as? String else { continue }
                if path.hasPrefix(collector.markerPrefix) {
                    if collector.replayed && !collector.markerSeen { collector.markerSeen = true; collector.marker.signal() }
                    continue
                }
                collector.paths.append(path)
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root, markerPath] as CFArray, eventID, 0, flags) else { return nil }
        let queue = DispatchQueue(label: "local.nuke.fsevents.history")
        FSEventStreamSetDispatchQueue(stream, queue)
        defer { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        guard FSEventStreamStart(stream) else { return nil }
        let deadline = DispatchTime.now() + timeout
        guard collector.replay.wait(timeout: deadline) == .success else { return nil }
        // A fresh write the stream must report before the answer counts.
        let marker = URL(fileURLWithPath: markerPath).appendingPathComponent("m")
        guard (try? Data(UUID().uuidString.utf8).write(to: marker)) != nil else { return nil }
        guard collector.marker.wait(timeout: deadline) == .success else { return nil }
        return queue.sync { collector.trustworthy ? collector.paths : nil }
    }
}
