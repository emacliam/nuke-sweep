import Foundation
import CoreServices
import Darwin

struct ScanOutput: Sendable { let result: ScanResult; let date: Date; let reused: Int }
struct BranchStamp: Equatable {
    let identity: FileIdentity
    let size: Int64
    let allocated: Int64
    let modified: Int64
    let changed: Int64
    let mode: UInt16
    static func read(_ url: URL) -> BranchStamp? {
        var s = stat(); guard lstat(url.path, &s) == 0 else { return nil }
        return .init(identity: .init(device: UInt64(s.st_dev), inode: UInt64(s.st_ino)), size: Int64(s.st_size), allocated: Int64(s.st_blocks) * 512, modified: Int64(s.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(s.st_mtimespec.tv_nsec), changed: Int64(s.st_ctimespec.tv_sec) &* 1_000_000_000 &+ Int64(s.st_ctimespec.tv_nsec), mode: s.st_mode)
    }
}
/// One recursive OS event stream. No polling traversal; overflow or root changes invalidate everything.
final class RecursiveChanges: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "local.nuke.file-events", qos: .utility)
    private let lock = NSLock()
    private var paths = Set<String>()
    private var all = true
    private let onChange: (@Sendable () -> Void)?
    init(_ root: URL, onChange: (@Sendable () -> Void)? = nil) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<RecursiveChanges>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            owner.lock.lock()
            if paths.count != count { owner.all = true }
            for index in 0..<min(count, paths.count) {
                let uncertainty = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
                if flags[index] & uncertainty != 0 || owner.paths.count >= 2048 { owner.all = true; owner.paths = []; break }
                owner.paths.insert(URL(fileURLWithPath: paths[index]).standardizedFileURL.path)
            }
            owner.lock.unlock(); owner.onChange?()
        }, &context, [root.resolvingSymlinksInPath().path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.35, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer))
        if let stream { FSEventStreamSetDispatchQueue(stream, queue); if !FSEventStreamStart(stream) { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil } }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); queue.sync {}; FSEventStreamRelease(stream) } }
    var available: Bool { stream != nil }
    func consume() -> (all: Bool, paths: Set<String>) {
        if let stream { FSEventStreamFlushSync(stream); queue.sync {} }
        lock.lock(); defer { lock.unlock() }
        let value = (all, paths); all = false; paths = []; return value
    }
}
final class IncrementalScanner: @unchecked Sendable {
    private struct Branch { let item: DiskItem; let stamp: BranchStamp; let categories: [String: Int64]; let date: Date }
    private var root: URL?
    private var rootID: FileIdentity?
    private var branches: [String: Branch] = [:]
    private var changes: RecursiveChanges?
    private let invalidation = NSLock()
    private var invalid = true
    func invalidate() { invalidation.lock(); invalid = true; invalidation.unlock() }
    /// Called only on DiskWork's serial queue. Cache summaries are bounded to 500 branches and 60 seconds.
    func scan(_ input: URL, token: ScanCancellation, force: Bool = false) -> ScanOutput {
        let now = Date()
        guard !token.cancelled else { return .init(result: ScanResult(items: [], skipped: 0, visited: 0, limited: true), date: now, reused: 0) }
        guard let original = BranchStamp.read(input), original.mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else {
            branches = [:]; changes = nil; root = nil; rootID = nil
            return .init(result: DiskScanner.scan(input, cancellation: token), date: now, reused: 0)
        }
        let root = input.resolvingSymlinksInPath().standardizedFileURL
        invalidation.lock(); let wasInvalid = invalid; invalid = false; invalidation.unlock()
        let identity = FileIdentity.read(root)
        if self.root != root || rootID != identity { branches = [:]; changes = RecursiveChanges(root); self.root = root; rootID = identity }
        let dirty = changes?.consume() ?? (all: true, paths: Set<String>())
        let full = force || wasInvalid || dirty.all || changes?.available != true
        guard let rootStamp = BranchStamp.read(root), rootStamp.mode & UInt16(S_IFMT) == UInt16(S_IFDIR) else { return .init(result: DiskScanner.scan(root, cancellation: token), date: now, reused: 0) }
        var result = ScanResult(items: [], skipped: 0, visited: 0, limited: false)
        var reused = 0, earliest = now, next: [String: Branch] = [:]
        let deadline = Date().addingTimeInterval(45)
        do {
            let complete = try DirectoryEntries.visit(root, shouldContinue: { !token.cancelled && !result.limited && result.visited < 250_000 && result.items.count < 10_000 && Date() <= deadline }) { rawChild in
                let child = rawChild.standardizedFileURL
                guard let stamp = BranchStamp.read(child) else { result.skipped += 1; return }
                let changed = dirty.paths.contains { $0 == root.path || $0 == child.path || $0.hasPrefix(child.path + "/") || child.path.hasPrefix($0 + "/") }
                if !full, !changed, let old = branches[child.path], old.stamp == stamp, now.timeIntervalSince(old.date) < 60, !old.item.incomplete {
                    result.items.append(old.item); for (key, value) in old.categories { result.categories[key, default: 0] += value }
                    reused += 1; earliest = min(earliest, old.date); if next.count < 500 { next[child.path] = old }; return
                }
                let directory = stamp.mode & UInt16(S_IFMT) == UInt16(S_IFDIR)
                let link = stamp.mode & UInt16(S_IFMT) == UInt16(S_IFLNK)
                if directory && stamp.identity.device != rootStamp.identity.device { result.skipped += 1; return }
                let scan = directory ? DiskScanner.scan(child, cancellation: token, limit: max(1, 250_000 - result.visited), deadline: deadline) : nil
                let allocated = stamp.allocated
                let item = DiskItem(url: child, size: scan?.logical ?? stamp.size, allocated: scan?.allocated ?? allocated, directory: directory, symlink: link, modified: nil, identity: stamp.identity, incomplete: scan.map { $0.skipped > 0 || $0.limited } ?? false)
                var categories = scan?.categories ?? [:]
                if !directory && !link { categories[GrowthComparison.category(child)] = item.size }
                result.items.append(item); result.visited += (scan?.visited ?? 0) + 1; result.skipped += scan?.skipped ?? 0
                if let scan { result.accessIssues += scan.accessIssues.prefix(max(0, 12 - result.accessIssues.count)) }
                for (key, value) in categories { result.categories[key, default: 0] += value }
                if next.count < 500, !item.incomplete { next[child.path] = Branch(item: item, stamp: stamp, categories: categories, date: now) }
                if scan?.limited == true { result = ScanResult(items: result.items, skipped: result.skipped, visited: result.visited, limited: true, categories: result.categories, accessIssues: result.accessIssues) }
            }
            if !complete { result.limited = true }
        } catch { result.skipped += 1; result.accessIssues.append(.init(path: root.path, reason: error.localizedDescription)) }
        branches = result.limited ? [:] : next
        return .init(result: ScanResult(items: result.items.sorted { $0.size > $1.size }, skipped: result.skipped, visited: result.visited, limited: result.limited, categories: result.categories, accessIssues: result.accessIssues), date: earliest, reused: reused)
    }
}
