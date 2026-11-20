import Darwin
import Foundation

// Approach and advice wording adapted from Major Tom
// (https://github.com/tjlondon-npauctions/majortom), MIT License,
// Copyright (c) 2026 Tom Jordan.

/// Something a delete had to leave behind, and what the person can do about it.
struct LeftBehind: Codable, Sendable, Hashable {
    let path: String
    let advice: String
}

struct TreeRemoval: Sendable {
    var removedBytes: Int64 = 0
    var leftBehind: [LeftBehind] = []
    var leftCount = 0
    var rootRemoved = false
    var complete: Bool { leftCount == 0 }
}

/// Deletes a file or folder entry by entry, carrying on past anything it
/// cannot remove, and says why each leftover stayed. Symlinks are removed, never
/// followed. Used for rebuildable caches and build output, which gain nothing
/// from Trash: their space only returns when Trash is emptied.
enum TreeRemover {
    static let maxReported = 20

    static func remove(_ url: URL, keepRoot: Bool = false) -> TreeRemoval {
        var result = TreeRemoval()
        var info = stat()
        guard lstat(url.path, &info) == 0 else { result.rootRemoved = true; return result }
        if info.st_mode & mode_t(S_IFMT) != mode_t(S_IFDIR) {
            if unlink(url.path) == 0 { result.removedBytes = Int64(info.st_blocks) * 512; result.rootRemoved = true }
            else { record(errno, url.path, into: &result) }
            return result
        }
        empty(url.path, into: &result, depth: 0)
        if !keepRoot {
            if rmdir(url.path) == 0 { result.rootRemoved = true }
            else if result.leftCount == 0 { record(errno, url.path, into: &result) }
        }
        return result
    }

    private static func empty(_ path: String, into result: inout TreeRemoval, depth: Int) {
        guard depth < 256 else { record(ENAMETOOLONG, path, into: &result); return }
        guard let directory = opendir(path) else { record(errno, path, into: &result); return }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        closedir(directory)
        for name in names {
            let child = path + "/" + name
            var info = stat()
            guard lstat(child, &info) == 0 else { continue }
            if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                empty(child, into: &result, depth: depth + 1)
                if rmdir(child) != 0, errno != ENOTEMPTY || result.leftCount == 0 { record(errno, child, into: &result) }
            } else if unlink(child) == 0 {
                result.removedBytes += Int64(info.st_blocks) * 512
            } else {
                record(errno, child, into: &result)
            }
        }
    }

    private static func record(_ code: Int32, _ path: String, into result: inout TreeRemoval) {
        result.leftCount += 1
        if result.leftBehind.count < maxReported {
            result.leftBehind.append(LeftBehind(path: path, advice: advice(path: path, errno: code)))
        }
    }

    static func advice(path: String, errno code: Int32) -> String {
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let simulator = path.contains("/CoreSimulator/") || path.contains("/Logs/CoreSimulator")
        switch code {
        case ENOTEMPTY:
            return simulator ? "kept being refilled by the iOS Simulator. Quit Simulator (or run `xcrun simctl shutdown all`) and try again."
                : "kept being refilled while it was deleted. Quit the app that writes here and try again."
        case EBUSY, ETXTBSY:
            return simulator ? "in use by the iOS Simulator. Quit Simulator and try again." : "in use. Quit the app using it and try again."
        case EXDEV: return "a volume is mounted here. Eject it first."
        case EROFS: return "on a read-only volume, so it can't be removed from here."
        case ENAMETOOLONG: return "nested too deeply to remove safely. Remove it yourself with `rm -rf \(quoted)`."
        case EPERM, EACCES:
            var info = stat()
            if lstat(path, &info) == 0 {
                if info.st_flags & UInt32(SF_RESTRICTED) != 0 { return "protected by System Integrity Protection. macOS doesn't allow removing it; leave it." }
                if info.st_flags & UInt32(SF_IMMUTABLE) != 0 { return "locked by the system. Nuke Sweep never uses admin rights; to remove it yourself run `sudo chflags -R noschg \(quoted) && sudo rm -rf \(quoted)`." }
                if info.st_flags & UInt32(UF_IMMUTABLE) != 0 { return "locked (Finder's Locked). Unlock it with `chflags -R nouchg \(quoted)` and try again." }
            }
            return "permission denied. If the folder belongs to another user or needs Full Disk Access, allow it and try again."
        default:
            return String(cString: strerror(code))
        }
    }
}
