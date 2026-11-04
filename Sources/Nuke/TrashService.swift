import Foundation
import CryptoKit
import Darwin

struct TrashEntry: Identifiable, Sendable {
    var id: String { item.id }
    let item: DiskItem
    let fingerprint: String
}
struct TrashSnapshot: Sendable {
    let rootIdentity: FileIdentity
    let entries: [TrashEntry]
    var size: Int64 { entries.reduce(0) { $0 + $1.item.size } }
}
/// Only instantiated with ~/.Trash in the application. Tests use isolated disposable directories.
struct TrashService: Sendable {
    let root: URL
    static let current = TrashService(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    enum Failure: LocalizedError {
        case inaccessible, changed, outsideRoot, tooLarge, cancelled
        var errorDescription: String? {
            switch self {
            case .cancelled: return "Trash inspection stopped. Scan again before cleanup."
            case .inaccessible: return "Nuke Sweep could not read Trash completely. Check macOS Privacy & Security → Full Disk Access, then scan again. No cleanup is available for an incomplete scan."
            case .changed: return "Trash or one of its items changed after the scan. Scan again before permanently deleting it."
            case .outsideRoot: return "Cleanup refused: the item is not directly inside this Trash folder."
            case .tooLarge: return "Trash exceeded the 250,000-entry inspection limit. Review or empty it in Finder instead."
            }
        }
    }
    private func rootIdentity() throws -> FileIdentity {
        var s = stat()
        guard lstat(root.path, &s) == 0, s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), s.st_uid == getuid() else { throw Failure.inaccessible }
        return FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino))
    }
    private func fingerprint(_ url: URL, token: ScanCancellation? = nil, deadline: Date = .distantFuture) throws -> String {
        var hash = SHA256(), count = 0
        func visit(_ path: URL) throws {
            if token?.cancelled == true { throw Failure.cancelled }
            guard Date() < deadline else { throw Failure.inaccessible }
            count += 1; guard count <= 250_000 else { throw Failure.tooLarge }
            var s = stat()
            guard lstat(path.path, &s) == 0 else { throw Failure.inaccessible }
            let record = "\(path.path)\0\(s.st_dev):\(s.st_ino):\(s.st_mode):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)\0"
            hash.update(data: Data(record.utf8))
            if s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                for child in try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) { try visit(child) }
            }
        }
        try visit(url)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func inspect(token: ScanCancellation = ScanCancellation()) throws -> TrashSnapshot {
        guard !token.cancelled else { throw Failure.cancelled }
        let deadline = Date().addingTimeInterval(60)
        let identity = try rootIdentity()
        let result = DiskScanner.scan(root, cancellation: token, deadline: deadline)
        if token.cancelled { throw Failure.cancelled }
        guard result.skipped == 0, !result.limited else { throw Failure.inaccessible }
        let entries = try result.items.map { item -> TrashEntry in
            guard item.identity != nil, !item.incomplete else { throw Failure.inaccessible }
            return TrashEntry(item: item, fingerprint: try fingerprint(item.url, token: token, deadline: deadline))
        }
        guard try rootIdentity() == identity else { throw Failure.changed }
        return TrashSnapshot(rootIdentity: identity, entries: entries)
    }
    func validate(_ entry: TrashEntry, rootIdentity expected: FileIdentity) throws {
        guard try rootIdentity() == expected else { throw Failure.changed }
        let parent = entry.item.url.deletingLastPathComponent().standardizedFileURL
        guard parent == root.standardizedFileURL else { throw Failure.outsideRoot }
        guard FileIdentity.read(entry.item.url) == entry.item.identity, try fingerprint(entry.item.url) == entry.fingerprint else { throw Failure.changed }
    }
    /// Deletes only the reviewed snapshot, never the Trash root or new top-level arrivals.
    func deleteReviewed(_ entries: [TrashEntry], rootIdentity: FileIdentity) -> [String] {
        do { for entry in entries { try validate(entry, rootIdentity: rootIdentity) } }
        catch { return ["Cleanup cancelled: \(error.localizedDescription)"] }
        return entries.map { entry in
            do {
                try validate(entry, rootIdentity: rootIdentity)
                try FileManager.default.removeItem(at: entry.item.url)
                return "Permanently deleted: \(entry.item.name)"
            } catch { return "Could not delete \(entry.item.name): \(error.localizedDescription)" }
        }
    }
}
