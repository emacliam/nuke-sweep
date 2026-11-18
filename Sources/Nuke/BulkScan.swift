import Darwin
import Foundation

/// One directory entry as `getattrlistbulk` returns it.
///
/// One system call fills a buffer with the name, type, sizes, identity and times
/// of many entries at once. The per-file `lstat` it replaces was most of the cost
/// of a scan: a folder of 10,000 files was 10,000 calls, and is now a handful.
struct BulkEntry {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var device: Int32
    var inode: UInt64
    var logical: Int64
    var allocated: Int64
    var modified: timespec
    var accessed: timespec
    var error: Int32
}

enum BulkDirectory {
    private static let bufferSize = 256 * 1024

    /// Reads every entry of the open directory `fd`. `body` returns false to stop.
    /// Returns false when stopped early. Throws the errno of a failed read.
    static func read(_ fd: Int32, _ body: (BulkEntry) -> Bool) throws -> Bool {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(bitPattern: ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_ACCTIME) | attrgroup_t(ATTR_CMN_FILEID)
        list.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH) | attrgroup_t(ATTR_FILE_DATAALLOCSIZE)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let count = getattrlistbulk(fd, &list, buffer, bufferSize, 0)
            if count < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if count == 0 { return true }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if !body(parse(entry)) { return false }
                entry += length
            }
        }
    }

    private static func parse(_ start: UnsafeMutableRawPointer) -> BulkEntry {
        var cursor = start + MemoryLayout<UInt32>.size
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size
        var result = BulkEntry(name: "", isDirectory: false, isSymlink: false, device: 0, inode: 0, logical: 0, allocated: 0,
                               modified: timespec(), accessed: timespec(), error: 0)
        let common = returned.commonattr
        if common & attrgroup_t(bitPattern: ATTR_CMN_ERROR) != 0 {
            result.error = Int32(bitPattern: cursor.loadUnaligned(as: UInt32.self)); cursor += 4
        }
        if common & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let reference = cursor.loadUnaligned(as: attrreference_t.self)
            let base = cursor + Int(reference.attr_dataoffset)
            result.name = String(cString: base.assumingMemoryBound(to: CChar.self))
            cursor += MemoryLayout<attrreference_t>.size
        }
        if common & attrgroup_t(ATTR_CMN_DEVID) != 0 {
            result.device = cursor.loadUnaligned(as: Int32.self); cursor += 4
        }
        if common & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            let type = cursor.loadUnaligned(as: UInt32.self); cursor += 4
            result.isDirectory = type == VDIR.rawValue
            result.isSymlink = type == VLNK.rawValue
        }
        if common & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            result.modified = cursor.loadUnaligned(as: timespec.self); cursor += MemoryLayout<timespec>.size
        }
        if common & attrgroup_t(ATTR_CMN_ACCTIME) != 0 {
            result.accessed = cursor.loadUnaligned(as: timespec.self); cursor += MemoryLayout<timespec>.size
        }
        if common & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            result.inode = cursor.loadUnaligned(as: UInt64.self); cursor += 8
        }
        let file = returned.fileattr
        if file & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            result.logical = cursor.loadUnaligned(as: Int64.self); cursor += 8
        }
        if file & attrgroup_t(ATTR_FILE_DATAALLOCSIZE) != 0 {
            result.allocated = cursor.loadUnaligned(as: Int64.self); cursor += 8
        }
        return result
    }
}

/// Shared, lock-guarded counters for a scan whose subtrees run in parallel.
final class ScanTally: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private(set) var visited = 0
    private(set) var skipped = 0
    private(set) var limited = false
    private(set) var categories: [String: Int64] = [:]
    private(set) var issues: [ScanAccessIssue] = []
    let limit: Int
    init(limit: Int) { self.limit = limit }

    /// Claims one entry against the budget. False once the budget is spent.
    func take() -> Bool {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        if visited >= limit { limited = true; return false }
        visited += 1
        return true
    }
    func markLimited() { os_unfair_lock_lock(&lock); limited = true; os_unfair_lock_unlock(&lock) }
    func skip(_ path: String?, _ reason: String?) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        skipped += 1
        if let path, let reason, issues.count < 12 { issues.append(.init(path: path, reason: reason)) }
    }
    func merge(_ local: [String: Int64]) {
        guard !local.isEmpty else { return }
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        for (key, value) in local { categories[key, default: 0] += value }
    }
}

/// The category of a file, as `GrowthComparison.category` decides it, split so
/// the path part is worked out once per directory rather than once per file.
enum FastCategory {
    static func forDirectory(_ path: String) -> String? {
        let lower = (path + "/").lowercased()
        if lower.contains("/node_modules/") || lower.contains("/deriveddata/") || lower.contains("/target/") || lower.contains("/.next/") { return "Developer artifacts" }
        if lower.contains("/caches/") || lower.contains("/.cache/") || lower.contains("/.npm/") { return "Caches" }
        if lower.contains("/.ollama/") || lower.contains("/.lmstudio/") || lower.contains("/huggingface/") { return "AI models and caches" }
        return nil
    }
    static func forFile(named name: String, inherited: String?) -> String {
        if let inherited { return inherited }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "Other files" }
        switch name[name.index(after: dot)...].lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "raw": return "Images"
        case "mov", "mp4", "mkv", "mp3", "wav", "m4a": return "Video and audio"
        case "zip", "dmg", "pkg", "tar", "gz", "ipa": return "Archives and installers"
        case "pdf", "docx", "txt", "md", "xlsx", "pages": return "Documents"
        default: return "Other files"
        }
    }
}
