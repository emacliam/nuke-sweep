import Foundation

struct StoredScan: Identifiable, Codable, Sendable {
    var id = UUID()
    let date: Date
    let root: String
    let sizes: [String: Int64]
    let categories: [String: Int64]
    var total: Int64 { sizes.values.reduce(0, +) }
}
struct GrowthRow: Identifiable {
    var id: String { name }
    let name: String
    let before: Int64
    let after: Int64
    var delta: Int64 { after - before }
}
enum GrowthComparison {
    static func rows(before: [String: Int64], after: [String: Int64]) -> [GrowthRow] {
        Set(before.keys).union(after.keys).map { GrowthRow(name: $0, before: before[$0] ?? 0, after: after[$0] ?? 0) }.sorted { abs($0.delta) > abs($1.delta) }
    }
    static func category(_ url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("/node_modules/") || path.contains("/deriveddata/") || path.contains("/target/") || path.contains("/.next/") { return "Developer artifacts" }
        if path.contains("/caches/") || path.contains("/.cache/") || path.contains("/.npm/") { return "Caches" }
        if path.contains("/.ollama/") || path.contains("/.lmstudio/") || path.contains("/huggingface/") { return "AI models and caches" }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "raw": return "Images"
        case "mov", "mp4", "mkv", "mp3", "wav", "m4a": return "Video and audio"
        case "zip", "dmg", "pkg", "tar", "gz", "ipa": return "Archives and installers"
        case "pdf", "docx", "txt", "md", "xlsx", "pages": return "Documents"
        default: return "Other files"
        }
    }
}
struct InventoryEntry: Identifiable, Sendable, Codable {
    var id: String { item.url.path }
    let item: DiskItem
    let category: String
    let owner: String
    let explanation: String
    var removable = true
}
struct InventoryReport: Sendable {
    var entries: [InventoryEntry] = []
    var notes: [String] = []
}
struct ProjectGroup: Identifiable, Sendable {
    var id: String { root.path }
    let root: URL
    let kind: String
    let entries: [InventoryEntry]
    var size: Int64 { entries.reduce(0) { $0 + $1.item.size } }
    var rebuildGuidance: String {
        switch kind {
        case "Deno / TypeScript": return "Recreate with deno task build or the project's documented Deno task."
        case "JavaScript / TypeScript": return "Reinstall dependencies with the project's package manager, then rebuild."
        case "Rust": return "Rebuild with cargo build (or cargo build --release)."
        case "Swift": return "Rebuild with swift build or the Xcode scheme."
        case "Go": return "Rebuild with go build ./... for the project's packages."
        case "Python": return "Recreate the virtual environment and reinstall project dependencies."
        case "Flutter / Dart": return "Run flutter pub get, then flutter build for the target."
        case "Java / Kotlin": return "Run the Gradle or Maven build described by the project."
        case ".NET": return "Run dotnet restore and dotnet build."
        default: return "Rebuild from source using the project's documented command."
        }
    }
}
struct ProjectDockerObject: Identifiable, Sendable {
    var id: String { kind + ":" + name }
    let kind: String
    let name: String
    let project: String
    let directory: String?
    let state: String
}
struct InstalledApp: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
}
struct DuplicateGroup: Identifiable, Sendable {
    var id: String { digest }
    let digest: String
    let files: [DiskItem]
    var extraBytes: Int64 { Int64(max(0, files.count - 1)) * (files.first?.size ?? 0) }
}
struct DuplicateReport: Sendable {
    let groups: [DuplicateGroup]
    let skipped: Int
    let limited: Bool
    let checked: Int
    var bytesRead: Int64 = 0
    var stopReason: String? = nil
    var inProgress = false
}
struct DuplicateProof: Sendable {
    let keeper: DiskItem
    let duplicate: DiskItem
}
struct OpenFileUse: Identifiable, Sendable {
    var id: String { "\(pid):\(path)" }
    let pid: Int32
    let process: String
    let path: String
}
struct OpenFileReport: Sendable {
    let uses: [OpenFileUse]
    let note: String
}
struct ReceiptItem: Identifiable, Codable, Sendable {
    var id = UUID()
    let originalPath: String
    let trashPath: String?
    let size: Int64
    let success: Bool
    let outcome: String
    var restoreEvidence: RestoreEvidence? = nil
    var restoredAt: Date? = nil
}
struct CleanupReceipt: Identifiable, Codable, Sendable {
    var id = UUID()
    let date: Date
    let title: String
    var items: [ReceiptItem]
    let freeBefore: Int64?
    let freeAfter: Int64?
    let undo: String
    var observedFreeDelta: Int64? {
        guard let before = freeBefore, let after = freeAfter else { return nil }
        return after - before
    }
}
struct MonitorSample: Sendable {
    let disk: ResourceSnapshot
    let cpu: Double?
    let memory: Int64?
    let date: Date
}
enum LocalStore {
    static var root: URL { AppEnvironment.supportRoot }
    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent(name).path)
    }
}
