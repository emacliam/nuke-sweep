import Foundation
import Darwin

/// Checks, before anything moves, whether the app's own restore would actually
/// work for each selected item.
///
/// The review already promises "open Finder Trash and choose Put Back". That is a
/// claim, not a check, and there are ordinary situations where it is simply
/// false — a read-only parent, or an item whose own ancestor is being trashed in
/// the same pass. Finding that out afterwards, when the only copy is in Trash and
/// Put Back is greyed out, is the worst possible moment.
///
/// Everything here mirrors what `ReceiptRestore.restore` genuinely requires:
/// the original parent must still exist, must be writable, and the original name
/// must be free. Nothing is modified; this only reads.
enum RestorePreflight {
    enum Outlook: Equatable, Sendable {
        /// The app's own restore should work.
        case restorable
        /// Trash will hold it, but automatic restore will not work. Finder's Put
        /// Back may still succeed, which is why this is not a refusal.
        case manualOnly(reason: String)

        var isRestorable: Bool { self == .restorable }
    }

    struct Finding: Identifiable, Equatable, Sendable {
        let item: DiskItem
        let outlook: Outlook
        var id: String { item.id }
        var reason: String? {
            if case .manualOnly(let reason) = outlook { return reason }
            return nil
        }
    }

    struct Report: Equatable, Sendable {
        let findings: [Finding]
        var manualOnly: [Finding] { findings.filter { !$0.outlook.isRestorable } }
        var allRestorable: Bool { manualOnly.isEmpty }
        var isEmpty: Bool { findings.isEmpty }
    }

    /// `selection` is the whole batch, because one item's restorability depends on
    /// the others: trashing a folder and something inside it in the same pass
    /// leaves the inner item with nowhere to go back to.
    static func inspect(_ selection: [DiskItem], token: ScanCancellation? = nil, writable: (URL) -> Bool = isWritable) -> Report {
        let paths = Set(selection.map { $0.url.standardizedFileURL.path })
        let findings = selection.prefix(while: { _ in token?.cancelled != true }).map { item -> Finding in
            Finding(item: item, outlook: outlook(for: item, inBatch: paths, writable: writable))
        }
        return Report(findings: findings)
    }

    private static func outlook(for item: DiskItem, inBatch paths: Set<String>, writable: (URL) -> Bool) -> Outlook {
        let parent = item.url.standardizedFileURL.deletingLastPathComponent()

        // An ancestor in the same batch means the folder this would be restored
        // into is itself going to Trash. Restore would have nowhere to put it.
        var ancestor = parent
        while true {
            if paths.contains(ancestor.path) {
                return .manualOnly(reason: "\(ancestor.lastPathComponent) is also being cleaned, so the folder this would return to will not exist.")
            }
            let next = ancestor.deletingLastPathComponent()
            if next.path == ancestor.path || next.path.isEmpty { break }
            ancestor = next
        }
        // Restore renames back into the original parent, which needs to be there.
        var info = stat()
        guard lstat(parent.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            return .manualOnly(reason: "The original folder could not be read, so its state at restore time is unknown.")
        }
        guard writable(parent) else {
            return .manualOnly(reason: "The original folder is not writable, so nothing can be moved back into it.")
        }
        return .restorable
    }

    static func isWritable(_ url: URL) -> Bool {
        access(url.path, W_OK) == 0
    }
}
