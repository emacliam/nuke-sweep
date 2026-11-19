import Foundation
import CryptoKit
import Darwin

/// Binds review to the measured tree, without reading file contents. This detects
/// changes across the review dialog; it does not claim atomicity against other writers.
enum ReviewSeal {
    struct Builder {
        private var leaves: [Data] = []
        private(set) var failure: Error?
        mutating func observe(_ url: URL) {
            guard failure == nil else { return }
            if CleanupSafety.isSensitive(url.standardizedFileURL.path) { failure = CleanupSafety.SafetyError.sensitive; return }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { failure = Failure.unreadable; return }
            guard leaves.count < 3_000_000 else { failure = Failure.incomplete; return }
            let record = "\(url.standardizedFileURL.path)\0\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)\0"
            leaves.append(Data(SHA256.hash(data: Data(record.utf8))))
        }
        func finish() throws -> String {
            if let failure { throw failure }
            var hash = SHA256()
            for leaf in leaves.sorted(by: { $0.lexicographicallyPrecedes($1) }) { hash.update(data: leaf) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
    /// The seal, built from the scanner's bulk directory reads on every core.
    /// Each entry contributes its path, identity, type, permissions, size and
    /// modification and change times; contents are never read.
    final class Collector: @unchecked Sendable {
        private var lock = os_unfair_lock()
        private var leaves: [Data] = []
        private var failure: Error?

        func observeRoot(_ url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { fail(Failure.unreadable); return }
            if CleanupSafety.isSensitive(url.standardizedFileURL.path) { fail(CleanupSafety.SafetyError.sensitive); return }
            append("\(url.path)\0root:\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)\0")
        }

        @Sendable func record(_ path: String, _ entry: BulkEntry) {
            if CleanupSafety.isSensitive(path) { fail(CleanupSafety.SafetyError.sensitive); return }
            append("\(path)\0\(entry.device):\(entry.inode):\(entry.type):\(entry.permissions):\(entry.logical):\(entry.modified.tv_sec):\(entry.modified.tv_nsec):\(entry.changed.tv_sec):\(entry.changed.tv_nsec)\0")
        }

        private func append(_ record: String) {
            let leaf = Data(SHA256.hash(data: Data(record.utf8)))
            os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
            guard leaves.count < 3_000_000 else { failure = failure ?? Failure.incomplete; return }
            leaves.append(leaf)
        }
        private func fail(_ error: Error) {
            os_unfair_lock_lock(&lock); if failure == nil { failure = error }; os_unfair_lock_unlock(&lock)
        }
        func finish() throws -> String {
            os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
            if let failure { throw failure }
            var hash = SHA256()
            for leaf in leaves.sorted(by: { $0.lexicographicallyPrecedes($1) }) { hash.update(data: leaf) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    static func capture(_ item: DiskItem, token: ScanCancellation = ScanCancellation(), deadline: Date = Date().addingTimeInterval(45)) throws -> String {
        let collector = Collector(); collector.observeRoot(item.url)
        if item.directory && !item.symlink {
            let scan = DiskScanner.scan(item.url, cancellation: token, deadline: deadline, respectIgnored: false, visit: collector.record, reuse: false)
            guard !token.cancelled, !scan.limited, scan.skipped == 0 else { throw Failure.incomplete }
        }
        guard !token.cancelled, Date() <= deadline else { throw Failure.incomplete }
        return try collector.finish()
    }
    /// Ids of reviewed folders that macOS's change record shows untouched since
    /// their review. One query for the whole batch. Anything not in the set,
    /// including every folder when the record cannot be trusted, is read and
    /// compared in full by `validate`.
    static func unchangedSinceReview(_ items: [DiskItem]) -> Set<String> {
        let folders = items.filter { $0.directory && !$0.symlink && $0.reviewEventID != nil && $0.reviewSeal != nil }
        guard let since = folders.compactMap(\.reviewEventID).min() else { return [] }
        let paths = folders.map { (id: $0.id, path: FSEventsHistory.canonical($0.url.path)) }
        guard let changed = FSEventsHistory.changes(since: since, under: paths.map(\.path)) else { return [] }
        let record = ScanReuse(remembered: [:], changed: changed)
        return Set(paths.filter { !record.dirty($0.path) }.map(\.id))
    }

    static func validate(_ item: DiskItem, unchangedSinceReview: Bool = false) throws {
        guard let expected = item.reviewSeal else { throw Failure.missing }
        if !unchangedSinceReview { guard try capture(item) == expected else { throw Failure.changed } }
        try GitInspection.inspect(item.url).requireUntracked()
    }
    enum Failure: LocalizedError {
        case missing, changed, incomplete, unreadable
        var errorDescription: String? {
            switch self {
            case .missing: return "This item has no completed cleanup review. Review it before moving it to Trash."
            case .changed: return "Contents changed after review. Nothing was moved for this item; inspect it and prepare a new review."
            case .incomplete: return "Could not finish verifying the reviewed contents. Select smaller folders and review again."
            case .unreadable: return "A reviewed item is unreadable or moved. Resolve access and review again."
            }
        }
    }
}
