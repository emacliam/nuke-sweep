import Foundation
import AppKit

enum ReceiptService {
    static func moveToTrash(_ items: [DiskItem], proofs: [DuplicateProof], runningAppPaths: [String], allowedRoots: [CleanupScope] = []) -> CleanupReceipt {
        let before = MachineService.snapshot().freeDisk
        // Verify the entire duplicate plan before changing anything, and retain its keeper.
        do {
            for proof in proofs {
                guard !items.contains(where: { $0.url == proof.keeper.url }), try DuplicateFinder.sameContents(proof.keeper, proof.duplicate) else { throw DuplicateFailure(message: "A duplicate or its keeper changed. Run duplicate detection again; no files were moved.") }
            }
        } catch {
            return CleanupReceipt(date: Date(), title: "Duplicate cleanup refused", items: items.map { .init(originalPath: $0.url.path, trashPath: nil, size: $0.size, success: false, outcome: error.localizedDescription) }, freeBefore: before, freeAfter: MachineService.snapshot().freeDisk, undo: "No files were moved.")
        }
        let outcomes = items.map { item -> ReceiptItem in
            do {
                try CleanupSafety.validate(item, allowedRoots: allowedRoots)
                try EmulatorCleanup.requireAndroidIdle(item.url)
                if item.url.pathExtension == "app", runningAppPaths.contains(where: { $0 == item.url.path || $0.hasPrefix(item.url.path + "/") }) { throw DuplicateFailure(message: "The application is running. Quit it and review again.") }
                if let proof = proofs.first(where: { $0.duplicate.id == item.id }), try !DuplicateFinder.sameContents(proof.keeper, proof.duplicate) { throw DuplicateFailure(message: "Duplicate contents changed. Run detection again.") }
                var destination: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &destination)
                return .init(originalPath: item.url.path, trashPath: destination?.path, size: item.size, success: true, outcome: "Moved to Trash")
            } catch { return .init(originalPath: item.url.path, trashPath: nil, size: item.size, success: false, outcome: error.localizedDescription) }
        }
        return CleanupReceipt(date: Date(), title: "File cleanup", items: outcomes, freeBefore: before, freeAfter: MachineService.snapshot().freeDisk, undo: "Open Finder Trash, locate the item, and choose Put Back when available. Otherwise drag it to its original path shown here. Restore is unavailable after Trash is emptied; no automatic restore overwrites files.")
    }
}
