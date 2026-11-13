import Foundation
import CryptoKit
import Darwin

/// One budget spans discovery, sampling, hashing and exact comparison. These
/// limits bound app work; a filesystem read already in the kernel can still wait.
struct DuplicateLimits: Sendable {
    var entries = 100_000
    var bytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    var seconds: TimeInterval = 120
}
private final class DuplicateBudget {
    let token: ScanCancellation
    let deadline: Date
    let maximum: Int64
    private(set) var read: Int64 = 0
    private(set) var reason: String?
    init(_ limits: DuplicateLimits, _ token: ScanCancellation) {
        self.token = token; deadline = Date().addingTimeInterval(max(0, limits.seconds)); maximum = max(0, limits.bytes)
    }
    func check() throws {
        if token.cancelled { reason = "Stopped" }
        else if Date() >= deadline { reason = "Time limit reached" }
        if let reason { throw DuplicateFailure(message: reason) }
    }
    func allowance(_ desired: Int) throws -> Int {
        try check()
        guard read < maximum else { reason = Self.readLimitReached; throw DuplicateFailure(message: Self.readLimitReached) }
        return Int(min(Int64(desired), maximum - read))
    }
    func record(_ count: Int) { read += Int64(count) }
    static let readLimitReached = "File-read limit reached"
    func exhausted() -> DuplicateFailure {
        reason = Self.readLimitReached
        return DuplicateFailure(message: Self.readLimitReached)
    }
}
private final class DuplicateReader {
    let handle: FileHandle
    let original: stat
    let item: DiskItem
    init(_ item: DiskItem) throws {
        // Never follow a swapped symlink or block opening a substituted pipe.
        let descriptor = open(item.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw DuplicateFailure(message: "File is unavailable.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              item.identity == FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), info.st_size == item.size else {
            close(descriptor); throw DuplicateFailure(message: "File identity or size changed.")
        }
        self.item = item; original = info; handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    func read(_ count: Int, budget: DuplicateBudget) throws -> Data {
        let amount = try budget.allowance(count)
        let data = try handle.read(upToCount: amount) ?? Data()
        budget.record(data.count); return data
    }
    func validate() throws {
        var now = stat()
        guard fstat(handle.fileDescriptor, &now) == 0,
              now.st_size == original.st_size,
              now.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec, now.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec,
              now.st_ctimespec.tv_sec == original.st_ctimespec.tv_sec, now.st_ctimespec.tv_nsec == original.st_ctimespec.tv_nsec,
              item.identity == FileIdentity.read(item.url) else { throw DuplicateFailure(message: "File changed while comparing.") }
    }
}
enum DuplicateFinder {
    static func digest(_ item: DiskItem, token: ScanCancellation) throws -> String {
        try digest(item, budget: DuplicateBudget(.init(), token))
    }
    private static func digest(_ item: DiskItem, budget: DuplicateBudget, prefix: Bool = false) throws -> String {
        let reader = try DuplicateReader(item)
        var hash = SHA256(), remaining = prefix ? min(item.size, 4096) : item.size
        while remaining > 0 {
            let data = try reader.read(Int(min(remaining, 1_048_576)), budget: budget)
            guard !data.isEmpty else { throw DuplicateFailure(message: "File size changed.") }
            hash.update(data: data); remaining -= Int64(data.count)
        }
        try budget.check(); try reader.validate()
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func sameContents(_ a: DiskItem, _ b: DiskItem, token: ScanCancellation = ScanCancellation()) throws -> Bool {
        try sameContents(a, b, budget: DuplicateBudget(.init(), token))
    }
    private static func sameContents(_ a: DiskItem, _ b: DiskItem, budget: DuplicateBudget) throws -> Bool {
        guard a.size == b.size, a.identity != b.identity else { return false }
        let x = try DuplicateReader(a), y = try DuplicateReader(b)
        var remaining = a.size
        while remaining > 0 {
            let left = try x.read(Int(min(remaining, 1_048_576)), budget: budget)
            guard !left.isEmpty else { return false }
            // A shared byte budget may leave a shorter allowance for the right
            // file. Refuse partial comparison instead of treating it as proof.
            let right = try y.read(left.count, budget: budget)
            if right.count != left.count {
                if budget.read >= budget.maximum { throw budget.exhausted() }
                throw DuplicateFailure(message: "Comparison incomplete.")
            }
            if left != right { return false }; remaining -= Int64(left.count)
        }
        try budget.check(); try x.validate(); try y.validate(); return true
    }
    static func find(_ root: URL, token: ScanCancellation, limit: Int = 100_000, limits: DuplicateLimits? = nil, progress: ((DuplicateReport) -> Void)? = nil) -> DuplicateReport {
        var limits = limits ?? DuplicateLimits(); limits.entries = min(limit, limits.entries)
        let budget = DuplicateBudget(limits, token)
        var rootStat = stat()
        guard lstat(root.path, &rootStat) == 0, rootStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return .init(groups: [], skipped: 1, limited: false, checked: 0) }
        var buckets: [Int64: [DiskItem]] = [:], skipped = 0, visited = 0, limited = false
        var identities = Set<String>(), groups: [DuplicateGroup] = [], lastPublication = Date.distantPast
        func report(_ inProgress: Bool) -> DuplicateReport {
            .init(groups: groups.sorted { $0.extraBytes == $1.extraBytes ? $0.id < $1.id : $0.extraBytes > $1.extraBytes }, skipped: skipped, limited: limited || budget.reason != nil, checked: visited, bytesRead: budget.read, stopReason: budget.reason ?? (limited ? "Entry limit reached" : nil), inProgress: inProgress)
        }
        func publish(force: Bool = false) {
            if force || Date().timeIntervalSince(lastPublication) >= 0.3 { lastPublication = Date(); progress?(report(true)) }
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else { return .init(groups: [], skipped: 1, limited: false, checked: 0) }
        for case let url as URL in enumerator {
            guard (try? budget.check()) != nil, visited < limits.entries else { limited = true; break }
            visited += 1; DiskWork.report(path: "Finding candidates · " + url.path, visited: visited)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { skipped += 1; continue }
            if info.st_dev != rootStat.st_dev { enumerator.skipDescendants(); skipped += 1; continue }
            guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), v.isSymbolicLink != true else { skipped += 1; continue }
            if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current && v.ubiquitousItemDownloadingStatus != .downloaded { skipped += 1; continue }
            guard v.isRegularFile == true, let item = InventoryService.measure(url), item.size > 0, let id = item.identity else { continue }
            guard identities.insert("\(id.device):\(id.inode)").inserted else { continue }
            buckets[item.size, default: []].append(item); publish()
        }
        // Prefixes are rejection filters only. Full hashes and byte comparison
        // still establish every displayed group, including partial scan results.
        outer: for size in buckets.keys.sorted(by: >) {
            guard let items = buckets[size], items.count > 1 else { continue }
            var samples: [String: [DiskItem]] = [:]
            for item in items {
                do { try budget.check(); DiskWork.report(path: "Sampling · " + item.url.path, visited: visited); samples[try digest(item, budget: budget, prefix: true), default: []].append(item); publish() }
                catch { if budget.reason != nil { break outer }; skipped += 1 }
            }
            for sampleKey in samples.keys.sorted() {
                guard let sample = samples[sampleKey], sample.count > 1 else { continue }
                var hashes: [String: [DiskItem]] = [:]
                for item in sample {
                    do { DiskWork.report(path: "Comparing contents · " + item.url.path, visited: visited); hashes[try digest(item, budget: budget), default: []].append(item); publish() }
                    catch { if budget.reason != nil { break outer }; skipped += 1 }
                }
                for hash in hashes.keys.sorted() {
                    guard let files = hashes[hash], files.count > 1 else { continue }
                    let ordered = files.sorted { $0.url.path < $1.url.path }
                    guard let keeper = ordered.first else { continue }
                    var confirmed = [keeper]
                    for item in ordered.dropFirst() {
                        do {
                            DiskWork.report(path: "Verifying copies · " + item.url.path, visited: visited)
                            if try sameContents(keeper, item, budget: budget) { confirmed.append(item) } else { skipped += 1 }
                        } catch { if budget.reason != nil { break }; skipped += 1 }
                    }
                    if confirmed.count > 1 { groups.append(.init(digest: hash, files: confirmed)); publish(force: groups.count == 1) }
                    if budget.reason != nil { break outer }
                }
            }
        }
        let final = report(false); progress?(final); return final
    }
}
