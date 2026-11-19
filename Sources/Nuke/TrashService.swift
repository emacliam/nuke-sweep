import Foundation
import CryptoKit
import Darwin

struct TrashEntry: Identifiable, Sendable {
    var id: String { item.id }
    let item: DiskItem
    let fingerprint: String
    /// False when it could not be fingerprinted; it is shown but cannot be deleted from here.
    var verifiable: Bool { !fingerprint.isEmpty }
}
struct TrashSnapshot: Sendable {
    let rootIdentity: FileIdentity
    let entries: [TrashEntry]
    var complete = true
    var size: Int64 { entries.reduce(0) { $0 + $1.item.size } }
    var verifiable: [TrashEntry] { entries.filter(\.verifiable) }
}
/// Only instantiated with ~/.Trash in the application. Tests use isolated disposable directories.
struct TrashService: Sendable {
    let root: URL
    static let current = TrashService(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    enum Failure: LocalizedError {
        case inaccessible, changed, outsideRoot, tooLarge, cancelled, ignored
        var errorDescription: String? {
            switch self {
            case .ignored: return "This item contains an ignored location."
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
    /// Identity, type, permissions, size and times of everything in the item,
    /// read in bulk on every core. Contents are never read. The same function
    /// runs again just before deletion, so any change in between is caught.
    private func fingerprint(_ url: URL, token: ScanCancellation? = nil, deadline: Date = .distantFuture) throws -> String {
        let collector = ReviewSeal.Collector(refuseSensitive: false)
        collector.observeRoot(url)
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw Failure.inaccessible }
        if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
            let scan = DiskScanner.scan(url, cancellation: token ?? ScanCancellation(), deadline: deadline, respectIgnored: false, visit: collector.record, reuse: false)
            if token?.cancelled == true { throw Failure.cancelled }
            guard !scan.limited else { throw Failure.tooLarge }
            guard scan.skipped == 0 else { throw Failure.inaccessible }
        }
        return try collector.finish()
    }
    func inspect(token: ScanCancellation = ScanCancellation()) throws -> TrashSnapshot {
        guard !token.cancelled else { throw Failure.cancelled }
        let identity = try rootIdentity()
        let result = DiskScanner.scan(root, cancellation: token, deadline: Date().addingTimeInterval(120))
        if token.cancelled { throw Failure.cancelled }
        let measuredCompletely = result.skipped == 0 && !result.limited
            && result.items.allSatisfy { $0.identity != nil && !$0.incomplete }
        guard measuredCompletely || !result.items.isEmpty else { throw Failure.inaccessible }
        // Each item is fingerprinted on its own time budget. One item that
        // cannot be verified is left unselectable; the rest stay usable.
        var entries: [TrashEntry] = []
        var complete = measuredCompletely
        for item in result.items {
            guard !token.cancelled else { throw Failure.cancelled }
            let seal = item.identity != nil && !item.incomplete
                ? try? fingerprint(item.url, token: token, deadline: Date().addingTimeInterval(60)) : nil
            if seal == nil { complete = false }
            entries.append(TrashEntry(item: item, fingerprint: seal ?? ""))
        }
        guard !token.cancelled else { throw Failure.cancelled }
        guard try rootIdentity() == identity else { throw Failure.changed }
        return TrashSnapshot(rootIdentity: identity, entries: entries, complete: complete)
    }

    func validate(_ entry: TrashEntry, rootIdentity expected: FileIdentity) throws {
        guard !IgnoredLocations.overlaps(entry.item.url, in: IgnoredLocations.paths) else { throw Failure.ignored }
        guard !entry.fingerprint.isEmpty else { throw Failure.inaccessible }
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
