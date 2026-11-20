import Foundation
import AppKit

enum ReceiptService {
    static func trash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
    static func moveToTrash(_ items: [DiskItem], proofs: [DuplicateProof], runningAppPaths: [String], allowedRoots: [CleanupScope] = [], developerScopes: [DeveloperScope] = [], deleteOutright: Set<String> = [], mover: (URL) throws -> URL? = trash) -> CleanupReceipt {
        let before = MachineService.snapshot().freeDisk
        // Verify the entire duplicate plan before changing anything, and retain its keeper.
        do {
            for proof in proofs {
                guard !items.contains(where: { covers($0, proof.keeper.url) }), try DuplicateFinder.sameContents(proof.keeper, proof.duplicate) else { throw DuplicateFailure(message: "A duplicate or its keeper changed, or the selection includes its keeper. Run duplicate detection again; no files were moved.") }
            }
        } catch {
            return CleanupReceipt(date: Date(), title: "Duplicate cleanup refused", items: items.map { .init(originalPath: $0.url.path, trashPath: nil, size: $0.size, success: false, outcome: error.localizedDescription) }, freeBefore: before, freeAfter: MachineService.snapshot().freeDisk, undo: "No files were moved.")
        }
        // One change-record query for every reviewed folder, instead of reading each again.
        let unchanged = ReviewSeal.unchangedSinceReview(items)
        let outcomes = items.enumerated().map { index, item -> ReceiptItem in
            // Shows which item is moving in the activity bar, so a long move never looks stuck.
            DiskWork.report(path: "\(index + 1) of \(items.count) · " + item.url.lastPathComponent, visited: index)
            do {
                try CleanupSafety.validate(item, allowedRoots: allowedRoots, developerScopes: developerScopes)
                try EmulatorCleanup.requireAndroidIdle(item.url)
                try ReviewSeal.validate(item, unchangedSinceReview: unchanged.contains(item.id))
                if item.url.pathExtension == "app", runningAppPaths.contains(where: { $0 == item.url.path || $0.hasPrefix(item.url.path + "/") }) { throw DuplicateFailure(message: "The application is running. Quit it and review again.") }
                for proof in proofs where covers(item, proof.duplicate.url) {
                    if try !DuplicateFinder.sameContents(proof.keeper, proof.duplicate) { throw DuplicateFailure(message: "Duplicate contents changed. Run detection again.") }
                }
                // Re-confirmed now, not trusted from the review: only something that
                // still classifies as rebuildable is deleted; anything else goes to
                // Trash. After Major Tom (MIT, (c) 2026 Tom Jordan).
                if deleteOutright.contains(item.id), CleanupEvidenceService.classify(item.url).kind.deletesOutright {
                    // Rebuildable: deleted now, so the space comes back now.
                    let removal = TreeRemover.remove(item.url)
                    if removal.complete && removal.rootRemoved {
                        return ReceiptItem(originalPath: item.url.path, trashPath: nil, size: item.size, success: true, outcome: "Deleted (rebuilds itself)")
                    }
                    let first = removal.leftBehind.first.map { URL(fileURLWithPath: $0.path).lastPathComponent + ": " + $0.advice } ?? "Some entries could not be removed."
                    return ReceiptItem(originalPath: item.url.path, trashPath: nil, size: item.size, success: removal.removedBytes > 0,
                                       outcome: "Partly deleted · \(bytes(removal.removedBytes)) freed, \(removal.leftCount) left. " + first)
                }
                let originalParent = FileIdentity.read(item.url.deletingLastPathComponent())
                let destination = try mover(item.url)
                var outcome = ReceiptItem(originalPath: item.url.path, trashPath: destination?.path, size: item.size, success: true, outcome: "Moved to Trash")
                if let destination, let originalParent,
                   let trashParent = FileIdentity.read(destination.deletingLastPathComponent()),
                   let trashedItem = FileIdentity.read(destination), trashedItem == item.identity {
                    outcome.restoreEvidence = .init(originalParent: originalParent, trashParent: trashParent, trashedItem: trashedItem)
                }
                return outcome
            } catch { return .init(originalPath: item.url.path, trashPath: nil, size: item.size, success: false, outcome: error.localizedDescription) }
        }
        return CleanupReceipt(date: Date(), title: "File cleanup", items: outcomes, freeBefore: before, freeAfter: MachineService.snapshot().freeDisk, undo: "Open Finder Trash, locate the item, and choose Put Back when available. Otherwise drag it to its original path shown here. Restore is unavailable after Trash is emptied; no automatic restore overwrites files.")
    }
    private static func covers(_ item: DiskItem, _ url: URL) -> Bool {
        item.url == url || (item.directory && !item.symlink && url.path.hasPrefix(item.url.path + "/"))
    }
}

/// Whether rebuildable items are deleted outright (default) or moved to Trash.
enum CleanupPreferences {
    private static let key = "nuke.deleteRebuildableOutright"
    static var deleteRebuildable: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Append-only record of every action, one JSON object per line, kept beside
/// the app's other data so it survives the in-app list's 100-entry limit.
/// Idea from Major Tom (MIT, (c) 2026 Tom Jordan).
enum HistoryLog {
    static var url: URL { AppEnvironment.supportRoot.appendingPathComponent("history.jsonl") }
    private static let queue = DispatchQueue(label: "local.nuke.history-log")
    static func append(title: String, detail: String) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        let line: [String: String] = ["date": ISO8601DateFormatter().string(from: Date()), "action": title, "detail": detail]
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
