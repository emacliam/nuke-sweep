import Foundation

struct MountedVolume: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let removable: Bool
    let internalVolume: Bool

    var id: String { url.path }
    var isRoot: Bool { url.standardizedFileURL.path == "/" }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
    var detail: String { bytes(free) + " free of " + bytes(total) }
}

enum MountedVolumeService {
    static func list() -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
            return MountedVolume(
                url: url,
                name: name,
                total: Int64(total),
                free: max(0, free),
                removable: values.volumeIsRemovable ?? false,
                internalVolume: values.volumeIsInternal ?? (url.path == "/")
            )
        }.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
            if lhs.internalVolume != rhs.internalVolume { return lhs.internalVolume }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
