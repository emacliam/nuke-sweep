import Foundation
import AppKit

enum ReceiptService {
    static func trash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
    static func moveToTrash(_ items: [DiskItem], proofs: [DuplicateProof], runningAppPaths: [String], allowedRoots: [CleanupScope] = [], developerScopes: [DeveloperScope] = [], mover: (URL) throws -> URL? = trash) -> CleanupReceipt {
        let before = MachineService.snapshot().freeDisk
        // Verify the entire duplicate plan before changing anything, and retain its keeper.
        do {
            for proof in proofs {
                guard !items.contains(where: { covers($0, proof.keeper.url) }), try DuplicateFinder.sameContents(proof.keeper, proof.duplicate) else { throw DuplicateFailure(message: "A duplicate or its keeper changed, or the selection includes its keeper. Run duplicate detection again; no files were moved.") }
            }
        } catch {
            return CleanupReceipt(date: Date(), title: "Duplicate cleanup refused", items: items.map { .init(originalPath: $0.url.path, trashPath: nil, size: $0.size, success: false, outcome: error.localizedDescription) }, freeBefore: before, freeAfter: MachineService.snapshot().freeDisk, undo: "No files were moved.")
        }
        let outcomes = items.map { item -> ReceiptItem in
            do {
                try CleanupSafety.validate(item, allowedRoots: allowedRoots, developerScopes: developerScopes)
                try EmulatorCleanup.requireAndroidIdle(item.url)
                try ReviewSeal.validate(item)
                if item.url.pathExtension == "app", runningAppPaths.contains(where: { $0 == item.url.path || $0.hasPrefix(item.url.path + "/") }) { throw DuplicateFailure(message: "The application is running. Quit it and review again.") }
                for proof in proofs where covers(item, proof.duplicate.url) {
                    if try !DuplicateFinder.sameContents(proof.keeper, proof.duplicate) { throw DuplicateFailure(message: "Duplicate contents changed. Run detection again.") }
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
