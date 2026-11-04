import Foundation

func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

enum Page: String, CaseIterable, Identifiable {
    case findSpace = "Find space", alerts = "Alerts"
    case permissions = "Permissions & access"
    case widgets = "Widgets"
    case growth = "Growth", projects = "Projects", apps = "Applications", startup = "Startup", duplicates = "Duplicates", ai = "Local models", devices = "Devices", monitor = "Menu-bar monitor"
    case overview = "Overview", storage = "Storage", developer = "Developer", trash = "Trash", docker = "Docker", processes = "Processes", watchlist = "Watchlist", history = "History"
    var id: String { rawValue }
    var icon: String {
        switch self { case .findSpace: return "sparkle.magnifyingglass"; case .alerts: return "bell"; case .permissions: return "hand.raised"; case .widgets: return "rectangle.3.group"; case .growth: return "chart.line.uptrend.xyaxis"; case .projects: return "folder.badge.gearshape"; case .apps: return "app.badge"; case .startup: return "power"; case .duplicates: return "square.on.square"; case .ai: return "cpu"; case .devices: return "iphone"; case .monitor: return "menubar.rectangle"; case .overview: return "square.grid.2x2"; case .storage: return "internaldrive"; case .developer: return "hammer"; case .trash: return "trash"; case .docker: return "shippingbox"; case .processes: return "waveform.path.ecg"; case .watchlist: return "eye"; case .history: return "clock.arrow.circlepath" }
    }
    var subtitle: String {
        switch self { case .findSpace: return "Review application caches, developer storage, and Trash."; case .alerts: return "Understand growth and choose what deserves attention."; case .permissions: return "Choose folder access and recover from denied scans."; case .widgets: return "Nuke Sweep at a glance, on your desktop."; case .growth: return "See what changed between complete folder scans."; case .projects: return "Build output, dependencies, and Compose resources by project."; case .apps: return "Review applications and the files that may belong to them."; case .startup: return "Inspect startup components and their observed owners."; case .duplicates: return "Compare exact file contents and choose a copy to keep."; case .ai: return "Understand local model storage before downloading it again."; case .devices: return "Archives and backups deserve a different kind of review."; case .monitor: return "A lightweight view of storage, CPU, and memory."; case .overview: return "A clearer picture of what’s on your Mac."; case .storage: return "Follow the space. Keep what matters."; case .developer: return "Build artifacts and caches, with the context to clean them."; case .trash: return "Review what’s in Trash before letting it go for good."; case .docker: return "Know what your containers leave behind."; case .processes: return "See what’s working, and what’s working too hard."; case .watchlist: return "Keep an eye on a folder as it changes."; case .history: return "A record of the changes you’ve made with Nuke Sweep." }
    }
}
struct FileIdentity: Equatable, Codable, Sendable {
    let device: UInt64
    let inode: UInt64
    static func read(_ url: URL) -> FileIdentity? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let inode = a[.systemFileNumber] as? NSNumber, let device = a[.systemNumber] as? NSNumber else { return nil }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }
}
struct DiskItem: Identifiable, Codable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let allocated: Int64
    let directory: Bool
    let symlink: Bool
    let modified: Date?
    let identity: FileIdentity?
    let incomplete: Bool
    var name: String { url.lastPathComponent }
}
struct ScanAccessIssue: Codable, Sendable {
    let path: String
    let reason: String
}
struct ScanResult: Codable, Sendable {
    var items: [DiskItem]
    var skipped: Int
    var visited: Int
    var limited: Bool
    var categories: [String: Int64] = [:]
    var accessIssues: [ScanAccessIssue] = []
    var logical: Int64 { items.reduce(0) { $0 + $1.size } }
    var allocated: Int64 { items.reduce(0) { $0 + $1.allocated } }
}
final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
struct CacheRule: Identifiable, Sendable {
    let id: String
    let name: String
    let relativePath: String
    let detail: String
    let symbol: String
    var url: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath) }
    static let all: [CacheRule] = [
        .init(id: "xcode", name: "Xcode Derived Data", relativePath: "Library/Developer/Xcode/DerivedData", detail: "Build products and indexes. Xcode will rebuild these; close Xcode and stop builds first.", symbol: "hammer"),
        .init(id: "npm", name: "npm cache", relativePath: ".npm/_cacache", detail: "Downloaded package content. Stop npm tasks first; packages may need downloading again.", symbol: "cube.box"),
        .init(id: "pip", name: "Python package cache", relativePath: "Library/Caches/pip", detail: "Downloaded wheels and HTTP cache. Stop pip tasks first; installs may need downloading again.", symbol: "curlybraces"),
        .init(id: "gradle", name: "Gradle caches", relativePath: ".gradle/caches", detail: "Dependency and build caches. Stop Gradle daemons and builds first; rebuilding can take time.", symbol: "wrench.and.screwdriver"),
        .init(id: "pnpm", name: "pnpm store", relativePath: "Library/pnpm/store", detail: "Content-addressable package store. Stop pnpm tasks first; packages may need re-linking or downloading again.", symbol: "shippingbox"),
        .init(id: "go", name: "Go build cache", relativePath: "Library/Caches/go-build", detail: "Compiled package cache. Stop Go builds first; go build repopulates it.", symbol: "terminal"),
        .init(id: "swiftpm", name: "SwiftPM cache", relativePath: "Library/Caches/org.swift.swiftpm", detail: "Downloaded Swift package checkouts and metadata. Stop builds first; SwiftPM downloads again.", symbol: "swift"),
        .init(id: "homebrew", name: "Homebrew cache", relativePath: "Library/Caches/Homebrew", detail: "Downloaded bottles and source archives. Homebrew downloads again if needed; brew cleanup is the native option.", symbol: "cup.and.saucer")
    ]
}
struct CacheMeasurement: Identifiable, Sendable {
    var id: String { rule.id }
    let rule: CacheRule
    let item: DiskItem?
    let skipped: Int
}
struct ProcessRow: Identifiable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let cpu: Double
    let memory: Int64
    let command: String
    let started: String
    let owner: UInt32
    var name: String { URL(fileURLWithPath: command).lastPathComponent }
}
struct Activity: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let title: String
    let detail: String
}
struct DockerUsage: Identifiable, Codable, Sendable {
    var id: String { type }
    let type: String
    let total: String
    let active: String
    let size: String
    let reclaimable: String
}
struct ResourceSnapshot: Sendable {
    var totalDisk: Int64 = 0
    var freeDisk: Int64 = 0
    var physicalMemory: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var load: Double = 0
    var processors = ProcessInfo.processInfo.activeProcessorCount
    var error: String?
    var usedDisk: Int64 { max(0, totalDisk - freeDisk) }
    var diskFraction: Double { totalDisk > 0 ? Double(usedDisk) / Double(totalDisk) : 0 }
}
