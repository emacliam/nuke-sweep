import Foundation

struct LocalModelRecord: Identifiable, Sendable {
    var id: String { root + "/" + name }
    let root: String
    let name: String
    let detail: String
}
/// Read-only metadata hints. Blob references are never treated as exclusively owned files.
enum LocalModelCatalog {
    private static func boundedManifest(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536 else { return nil }
        return data
    }
    static func inspect(_ entries: [InventoryEntry], token: ScanCancellation) -> [LocalModelRecord] {
        var records: [LocalModelRecord] = []
        let deadline = Date().addingTimeInterval(3)
        for entry in entries {
            guard !token.cancelled, Date() < deadline else { break }
            let root = entry.item.url
            guard !entry.item.symlink else { continue }
            if entry.owner == "Ollama" {
                let manifests = root.appendingPathComponent("manifests")
                guard (try? manifests.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                      let enumerator = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                var visited = 0
                for case let url as URL in enumerator {
                    visited += 1
                    if token.cancelled || Date() >= deadline || visited > 2000 || records.count >= 100 { break }
                    guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else { continue }
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 65_536,
                          let data = boundedManifest(url),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let layers = json["layers"] as? [[String: Any]] else { continue }
                    let name = String(url.path.dropFirst(manifests.path.count + 1))
                    records.append(.init(root: root.path, name: name, detail: "Ollama manifest · \(layers.count) layer references; layers can be shared. Manage individual models in Ollama."))
                }
            } else {
                let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
                for url in children.prefix(100) {
                    if token.cancelled || Date() >= deadline || records.count >= 100 { break }
                    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    let isHub = entry.owner == "Hugging Face"
                    if isHub && !url.lastPathComponent.hasPrefix("models--") { continue }
                    records.append(.init(root: root.path, name: isHub ? url.lastPathComponent.replacingOccurrences(of: "models--", with: "").replacingOccurrences(of: "--", with: "/") : url.lastPathComponent, detail: isHub ? "Repository directory · snapshots may share blobs; not proof of active use." : "Directory name only · model identity and active use are unverified."))
                }
            }
        }
        return records
    }
}
