import Darwin
import Foundation

struct RestoreEvidence: Codable, Sendable {
    let originalParent: FileIdentity
    let trashParent: FileIdentity
    let trashedItem: FileIdentity
}

enum ReceiptRestore {
    static func restore(_ item: ReceiptItem) throws {
        guard item.success, item.restoredAt == nil, let evidence = item.restoreEvidence,
              let trashPath = item.trashPath, trashPath.hasPrefix("/"),
              item.originalPath.hasPrefix("/") else {
            throw Failure("Use Put Back in Finder for this receipt.")
        }
        let source = URL(fileURLWithPath: trashPath).standardizedFileURL
        let destination = URL(fileURLWithPath: item.originalPath).standardizedFileURL
        let sourceParent = try openParent(source, expected: evidence.trashParent)
        defer { close(sourceParent) }
        let destinationParent = try openParent(destination, expected: evidence.originalParent)
        defer { close(destinationParent) }

        var info = stat()
        guard fstatat(sourceParent, source.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              identity(info) == evidence.trashedItem else {
            throw Failure("The Trash copy is missing or has changed. Check it in Finder.")
        }
        // Anchor both paths to the verified directories. The exclusive rename
        // also rejects an occupied destination that appears during restoration.
        guard renameatx_np(sourceParent, source.lastPathComponent, destinationParent,
                           destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { throw Failure("The original path already exists. Choose a different location in Finder.") }
            throw Failure("Could not restore this item. " + String(cString: strerror(code)))
        }
    }

    private static func openParent(_ item: URL, expected: FileIdentity) throws -> Int32 {
        let parent = item.deletingLastPathComponent()
        let descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure("A parent folder is missing or inaccessible. Check the original location and Trash in Finder.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, identity(info) == expected else {
            close(descriptor)
            throw Failure("A parent folder has changed since cleanup. Choose the restore location in Finder.")
        }
        return descriptor
    }

    private static func identity(_ info: stat) -> FileIdentity {
        .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
