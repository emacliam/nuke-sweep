import CryptoKit
import Darwin
import Foundation

// Design adapted from Major Tom's NAS offload
// (https://github.com/tjlondon-npauctions/majortom), MIT License,
// Copyright (c) 2026 Tom Jordan.

/// One item copied to another drive, verified, and recorded.
struct OffloadRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    let originalPath: String
    let copyPath: String
    let date: Date
    let bytes: Int64
    let files: Int
    /// Relative path → SHA-256 (or size+head/tail fingerprint above the cap).
    let hashes: [String: String]
    var restored: Date?
}

enum OffloadError: LocalizedError {
    case sameVolume, destinationMissing, copyFailed(String), verifyFailed(String), originalChanged, exists
    var errorDescription: String? {
        switch self {
        case .sameVolume: return "Choose a folder on another drive. Copying to the same disk frees nothing."
        case .destinationMissing: return "The destination folder is not available. Connect the drive and try again."
        case .copyFailed(let why): return "The copy failed, so the original was kept: \(why)"
        case .verifyFailed(let path): return "The copy did not match the original (\(path)), so the original was kept and the copy removed."
        case .originalChanged: return "The original changed while it was being copied, so it was kept. Try again when nothing is writing to it."
        case .exists: return "Something with that name already exists in the destination."
        }
    }
}

enum OffloadEngine {
    static let fullHashCap: Int64 = 1_000_000_000

    /// Copy, verify, record, then move the original to Trash. Any failure keeps
    /// the original and removes the partial copy.
    static func offload(_ source: URL, to destination: URL, token: ScanCancellation = ScanCancellation(),
                        log: Bool = true, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> OffloadRecord {
        var sourceInfo = stat(), destinationInfo = stat()
        guard lstat(destination.path, &destinationInfo) == 0 else { throw OffloadError.destinationMissing }
        guard lstat(source.path, &sourceInfo) == 0 else { throw OffloadError.copyFailed("the original is gone") }
        guard sourceInfo.st_dev != destinationInfo.st_dev else { throw OffloadError.sameVolume }
        let target = destination.appendingPathComponent(safeName(source.lastPathComponent))
        guard !FileManager.default.fileExists(atPath: target.path) else { throw OffloadError.exists }

        let before = try seal(source, token: token)
        // Copied under a temporary name, verified there, then renamed into place
        // with RENAME_EXCL, so nothing existing is ever overwritten and a
        // half-finished copy never looks complete. ditto keeps permissions,
        // extended attributes and resource forks.
        let partial = destination.appendingPathComponent(".nuke-partial-" + UUID().uuidString.prefix(8) + "-" + target.lastPathComponent)
        let copy = CommandRunner.run("/usr/bin/ditto", [source.path, partial.path], timeout: 6 * 3600)
        guard copy.status == 0 else { try? FileManager.default.removeItem(at: partial); throw OffloadError.copyFailed(copy.output.suffix(200).description) }
        _ = CommandRunner.run("/bin/sync", [], timeout: 120)

        let originals = try fingerprints(of: source, token: token)
        let copies = try fingerprints(of: partial, token: token, uncached: true)
        if let mismatch = originals.first(where: { copies[$0.key] != $0.value })?.key ?? (originals.count == copies.count ? nil : "file count") {
            try? FileManager.default.removeItem(at: partial)
            throw OffloadError.verifyFailed(mismatch)
        }
        guard renamex_np(partial.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw OffloadError.exists
        }
        let after = try seal(source, token: token)
        guard before == after else { try? FileManager.default.removeItem(at: target); throw OffloadError.originalChanged }

        let bytes = DiskScanner.scan(source, cancellation: token, respectIgnored: false, reuse: false).logical + (sourceInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) ? 0 : Int64(sourceInfo.st_size))
        let record = OffloadRecord(originalPath: source.path, copyPath: target.path, date: Date(), bytes: bytes, files: originals.count, hashes: originals)
        // The manifest travels with the copy, so another Mac can find it too.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(record).write(to: destination.appendingPathComponent(target.lastPathComponent + ".nuke-offload.json"))
        if log { OffloadLog.append(record) }
        // Last, and only after everything above: the original goes to Trash, never deleted.
        try trash(source)
        return record
    }

    /// Copies an offloaded item back to where it was (or `to`), verifying it.
    static func restore(_ record: OffloadRecord, to: URL? = nil, token: ScanCancellation = ScanCancellation(), log: Bool = true) throws -> URL {
        let target = to ?? URL(fileURLWithPath: record.originalPath)
        guard FileManager.default.fileExists(atPath: record.copyPath) else { throw OffloadError.destinationMissing }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw OffloadError.exists }
        let copy = CommandRunner.run("/usr/bin/ditto", [record.copyPath, target.path], timeout: 6 * 3600)
        guard copy.status == 0 else { try? FileManager.default.removeItem(at: target); throw OffloadError.copyFailed(copy.output.suffix(200).description) }
        let restored = try fingerprints(of: target, token: token, uncached: true)
        if let mismatch = record.hashes.first(where: { restored[$0.key] != $0.value })?.key {
            try? FileManager.default.removeItem(at: target)
            throw OffloadError.verifyFailed(mismatch)
        }
        if log { OffloadLog.markRestored(record.id) }
        return target
    }

    /// Identity, sizes and times of everything in the item. Your own files may
    /// hold keys and repositories, so nothing is refused for that here.
    private static func seal(_ url: URL, token: ScanCancellation) throws -> String {
        let collector = ReviewSeal.Collector(refuseSensitive: false)
        collector.observeRoot(url)
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
            let scan = DiskScanner.scan(url, cancellation: token, deadline: Date().addingTimeInterval(600), respectIgnored: false, visit: collector.record, reuse: false)
            guard !scan.limited, scan.skipped == 0 else { throw OffloadError.copyFailed("could not read all of it") }
        }
        return try collector.finish()
    }

    /// SMB and exFAT reject some characters; keep names portable.
    static func safeName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "\\:*?\"<>|")
        return String(name.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
    }

    /// Relative path → content fingerprint for every regular file under `root`.
    static func fingerprints(of root: URL, token: ScanCancellation, uncached: Bool = false) throws -> [String: String] {
        var result: [String: String] = [:]
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw OffloadError.copyFailed("missing \(root.path)") }
        if info.st_mode & mode_t(S_IFMT) != mode_t(S_IFDIR) {
            result[root.lastPathComponent] = try hash(root.path, size: Int64(info.st_size), uncached: uncached)
            return result
        }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [])
        while let url = enumerator?.nextObject() as? URL {
            if token.cancelled { throw OffloadError.copyFailed("stopped") }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result[relative] = try hash(url.path, size: Int64(values.fileSize ?? 0), uncached: uncached)
        }
        return result
    }

    /// Full SHA-256 up to the cap; above it, size plus the first and last 16 MB.
    /// `uncached` reads the copy from the disk rather than memory (F_NOCACHE).
    private static func hash(_ path: String, size: Int64, uncached: Bool) throws -> String {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw OffloadError.verifyFailed(path) }
        defer { close(fd) }
        if uncached { _ = fcntl(fd, F_NOCACHE, 1) }
        var hasher = SHA256()
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)
        func read(from offset: Int64, count: Int64) {
            var done: Int64 = 0
            while done < count {
                let want = Int(min(Int64(chunk), count - done))
                let got = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, want, off_t(offset + done)) }
                if got <= 0 { break }
                hasher.update(data: Data(buffer[0..<got])); done += Int64(got)
            }
        }
        if size <= fullHashCap {
            read(from: 0, count: size)
        } else {
            let edge: Int64 = 16 << 20
            hasher.update(data: Data("\(size)".utf8))
            read(from: 0, count: edge); read(from: size - edge, count: edge)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Local record of everything offloaded, alongside the manifests on the drives.
enum OffloadLog {
    static var url: URL { AppEnvironment.supportRoot.appendingPathComponent("offloads.json") }
    static func all() -> [OffloadRecord] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([OffloadRecord].self, from: $0) } ?? []
    }
    static func save(_ records: [OffloadRecord]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(records).write(to: url, options: .atomic)
    }
    static func append(_ record: OffloadRecord) { save([record] + all()) }
    static func markRestored(_ id: UUID) {
        save(all().map { var r = $0; if r.id == id { r.restored = Date() }; return r })
    }
}

extension OffloadLog {
    /// Reads the manifests written beside offloaded copies on a drive, for copies
    /// made on another Mac or before a reinstall. Returns how many were new.
    static func importManifests(in folder: URL) -> Int {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var records = all()
        let known = Set(records.map(\.copyPath))
        var added = 0
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".nuke-offload.json") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  var record = try? decoder.decode(OffloadRecord.self, from: data) else { continue }
            // The drive may be mounted elsewhere now; trust where the copy is today.
            let copy = folder.appendingPathComponent(String(name.dropLast(".nuke-offload.json".count)))
            guard FileManager.default.fileExists(atPath: copy.path), !known.contains(copy.path) else { continue }
            record = OffloadRecord(id: record.id, originalPath: record.originalPath, copyPath: copy.path, date: record.date,
                                   bytes: record.bytes, files: record.files, hashes: record.hashes, restored: record.restored)
            records.insert(record, at: 0); added += 1
        }
        save(records)
        return added
    }
}
