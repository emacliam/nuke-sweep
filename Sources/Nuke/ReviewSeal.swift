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
            guard leaves.count < 250_001 else { failure = Failure.incomplete; return }
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
    static func capture(_ item: DiskItem, token: ScanCancellation = ScanCancellation(), deadline: Date = Date().addingTimeInterval(45)) throws -> String {
        var builder = Builder(); builder.observe(item.url)
        if item.directory && !item.symlink {
            let scan = DiskScanner.scan(item.url, cancellation: token, deadline: deadline, observing: { builder.observe($0) })
            guard !token.cancelled, !scan.limited, scan.skipped == 0 else { throw Failure.incomplete }
        }
        guard !token.cancelled, Date() <= deadline else { throw Failure.incomplete }
        return try builder.finish()
    }
    static func validate(_ item: DiskItem) throws {
        guard let expected = item.reviewSeal else { throw Failure.missing }
        guard try capture(item) == expected else { throw Failure.changed }
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
