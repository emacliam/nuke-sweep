import Foundation
import Darwin

enum FolderListing {
    /// Names and file metadata only. Never walks into child directories.
    static func inspect(_ root: URL, token: ScanCancellation, excluding: @Sendable (URL) -> Bool = { _ in false }, limit: Int = 10_000, budget: TimeInterval = 2) -> ScanResult {
        var result = ScanResult(items: [], skipped: 0, visited: 0, limited: false)
        let deadline = Date().addingTimeInterval(budget)
        var rootInfo = stat()
        guard !token.cancelled, lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { result.skipped = 1; return result }
        do {
            let complete = try DirectoryEntries.visit(root, shouldContinue: { !token.cancelled && result.visited < limit && Date() < deadline }) { child in
                guard !excluding(child) else { return }
                result.visited += 1
                var info = stat()
                guard lstat(child.path, &info) == 0 else { result.skipped += 1; return }
                let directory = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
                let link = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
                if directory && info.st_dev != rootInfo.st_dev { result.skipped += 1; return }
                var item = DiskItem(url: child, size: directory ? 0 : Int64(info.st_size), allocated: directory ? 0 : Int64(info.st_blocks) * 512, directory: directory, symlink: link, modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)), accessed: Date(timeIntervalSince1970: Double(info.st_atimespec.tv_sec)), identity: .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), incomplete: directory)
                item.measurementPending = directory
                result.items.append(item)
            }
            result.limited = !complete
        } catch { result.skipped += 1; result.accessIssues = [.init(path: root.path, reason: error.localizedDescription)] }
        result.items.sort { a, b in a.directory != b.directory ? a.directory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        return result
    }
    /// A shared budget prevents a wide expansion from queuing thousands of full
    /// scans. Remaining folders stay explicitly unmeasured and can be measured on demand.
    static func measure(_ items: [DiskItem], token: ScanCancellation, excluding: @Sendable (URL) -> Bool, budget: TimeInterval = 6) -> [DiskItem] {
        let deadline = Date().addingTimeInterval(budget)
        return items.map { item in
            guard item.measurementPending == true, !token.cancelled, Date() < deadline,
                  FileIdentity.read(item.url) == item.identity else { return item }
            let scan = DiskScanner.scan(item.url, cancellation: token, limit: 12_000, deadline: deadline, excluding: excluding)
            var measured = DiskItem(url: item.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: item.modified, identity: item.identity, incomplete: scan.limited || scan.skipped > 0)
            measured.measurementPending = false
            return measured
        }
    }
}
