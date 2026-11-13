import Foundation

enum CleanupEvidenceKind: String, Codable, Sendable {
    case knownCache
    case dependency
    case buildOutput
    case gitIgnored
    case projectRoot
    case sourceLike
    case sensitive
    case unknown

    var supportsContentsReview: Bool {
        self == .knownCache || self == .dependency || self == .buildOutput
    }

    var label: String {
        switch self {
        case .knownCache: return "Cache"
        case .dependency: return "Dependencies"
        case .buildOutput: return "Build output"
        case .gitIgnored: return "Git-ignored"
        case .projectRoot: return "Project source"
        case .sourceLike: return "Source-like"
        case .sensitive: return "Protected"
        case .unknown: return "Unknown"
        }
    }
    var isBlocked: Bool { self == .projectRoot || self == .sourceLike || self == .sensitive }
}

struct CleanupEvidence: Codable, Sendable, Equatable {
    let kind: CleanupEvidenceKind
    let detail: String
    let rebuild: String?
    let gitIgnored: Bool
    var label: String { kind.label }
}

/// Cheap, honest evidence labels. The review plan adds a git check-ignore probe;
/// the tree uses the path/name/project-marker heuristics only.
enum CleanupEvidenceService {
    private struct CachePath {
        let prefix: String
        let detail: String
        let rebuild: String
    }

    private static let caches: [CachePath] = {
        let h = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return [
            .init(prefix: h + "/Library/Developer/Xcode/DerivedData", detail: String(localized: "Xcode build products and indexes."), rebuild: String(localized: "Xcode rebuilds products and indexes on the next build.")),
            .init(prefix: h + "/Library/Caches", detail: String(localized: "An application or tool cache."), rebuild: String(localized: "Applications and tools rebuild caches as needed.")),
            .init(prefix: h + "/.npm/_cacache", detail: String(localized: "Downloaded npm package content."), rebuild: String(localized: "npm downloads packages again.")),
            .init(prefix: h + "/Library/pnpm/store", detail: String(localized: "The pnpm content-addressable store."), rebuild: String(localized: "pnpm re-links or re-downloads packages.")),
            .init(prefix: h + "/.cargo/registry", detail: String(localized: "Downloaded Cargo crate sources."), rebuild: String(localized: "Cargo downloads crates again.")),
            .init(prefix: h + "/Library/Caches/go-build", detail: String(localized: "The Go build cache."), rebuild: String(localized: "go build repopulates the cache.")),
            .init(prefix: h + "/Library/Caches/org.swift.swiftpm", detail: String(localized: "Swift package download cache."), rebuild: String(localized: "SwiftPM downloads packages again.")),
            .init(prefix: h + "/Library/Caches/Homebrew", detail: String(localized: "Downloaded Homebrew bottles and sources."), rebuild: String(localized: "Homebrew downloads again if needed.")),
            .init(prefix: h + "/.gradle/caches", detail: String(localized: "Gradle dependency and build caches."), rebuild: String(localized: "Gradle re-downloads dependencies.")),
            .init(prefix: h + "/Library/Caches/pip", detail: String(localized: "Downloaded Python wheels and HTTP cache."), rebuild: String(localized: "pip downloads packages again.")),
            .init(prefix: h + "/Library/Caches/CocoaPods", detail: String(localized: "CocoaPods spec and pod cache."), rebuild: String(localized: "pod install downloads again.")),
            // Xcode leaves most of its bulk outside DerivedData. Without these the
            // largest folders on a developer's Mac report no evidence at all, which
            // reads as "unknown" when their purpose is in fact well understood.
            .init(prefix: h + "/Library/Developer/Xcode/iOS DeviceSupport", detail: String(localized: "Symbol files cached per connected iOS device and build. Xcode re-downloads them the next time that device is attached."), rebuild: String(localized: "Xcode re-fetches symbols when the device is connected again.")),
            .init(prefix: h + "/Library/Developer/Xcode/watchOS DeviceSupport", detail: String(localized: "Symbol files cached per connected watchOS device and build."), rebuild: String(localized: "Xcode re-fetches symbols when the device is connected again.")),
            .init(prefix: h + "/Library/Developer/Xcode/tvOS DeviceSupport", detail: String(localized: "Symbol files cached per connected tvOS device and build."), rebuild: String(localized: "Xcode re-fetches symbols when the device is connected again.")),
            .init(prefix: h + "/Library/Developer/Xcode/macOS DeviceSupport", detail: String(localized: "Symbol files cached per connected macOS device and build."), rebuild: String(localized: "Xcode re-fetches symbols when the device is connected again.")),
            .init(prefix: h + "/Library/Developer/Xcode/DocumentationCache", detail: String(localized: "Downloaded Xcode documentation content."), rebuild: String(localized: "Xcode downloads documentation again when browsed.")),
            .init(prefix: h + "/Library/Developer/Xcode/DocumentationIndex", detail: String(localized: "Generated index over downloaded Xcode documentation."), rebuild: String(localized: "Xcode rebuilds the documentation index.")),
            .init(prefix: h + "/Library/Developer/Xcode/iOS Device Logs", detail: String(localized: "Crash and diagnostic logs copied from connected devices."), rebuild: String(localized: "Not regenerated; copy anything you still need before removing.")),
            .init(prefix: h + "/Library/Developer/Xcode/UserData/IB Support", detail: String(localized: "Interface Builder support cache."), rebuild: String(localized: "Xcode recreates it as needed.")),
            .init(prefix: h + "/Library/Developer/CoreSimulator/Caches", detail: String(localized: "Simulator runtime and device caches."), rebuild: String(localized: "The simulator repopulates them on next use.")),
            .init(prefix: h + "/Library/Developer/XCPGDevices", detail: String(localized: "Playground simulator devices created by Xcode."), rebuild: String(localized: "Xcode recreates playground devices on demand.")),
            .init(prefix: h + "/.cache", detail: String(localized: "A tool cache directory following the XDG convention."), rebuild: String(localized: "The owning tool repopulates it as needed.")),
            .init(prefix: h + "/Library/Caches/ms-playwright", detail: String(localized: "Downloaded Playwright browser builds."), rebuild: String(localized: "npx playwright install downloads them again.")),
            .init(prefix: h + "/Library/Caches/deno", detail: String(localized: "Deno module and build cache."), rebuild: String(localized: "Deno re-downloads modules on next run.")),
            .init(prefix: h + "/.bun/install/cache", detail: String(localized: "Bun package install cache."), rebuild: String(localized: "bun install downloads packages again.")),
            .init(prefix: h + "/.m2/repository", detail: String(localized: "Downloaded Maven artifacts."), rebuild: String(localized: "Maven downloads dependencies again.")),
            .init(prefix: h + "/.nuget/packages", detail: String(localized: "Downloaded NuGet packages."), rebuild: String(localized: "dotnet restore downloads packages again.")),
            .init(prefix: h + "/go/pkg/mod", detail: String(localized: "Downloaded Go module sources."), rebuild: String(localized: "go mod download fetches modules again.")),
            .init(prefix: h + "/.rustup/toolchains", detail: String(localized: "Installed Rust toolchains."), rebuild: String(localized: "rustup reinstalls a toolchain on demand.")),
            .init(prefix: h + "/.pub-cache", detail: String(localized: "Downloaded Dart and Flutter packages."), rebuild: String(localized: "pub get downloads packages again."))
        ]
    }()

    /// Xcode writes these beside its caches, but they are products rather than
    /// caches: removing one loses the only copy, so they are evidenced as build
    /// output with an explicit warning instead of being called a cache.
    private static let archives: [CachePath] = {
        let h = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return [
            .init(prefix: h + "/Library/Developer/Xcode/Archives", detail: String(localized: "Built app archives kept for distribution and crash symbolication. These are products, not a cache: nothing regenerates them except another archive build."), rebuild: String(localized: "Only a new archive build recreates these. Keep any archive matching a release you still support.")),
            .init(prefix: h + "/Library/Developer/Xcode/Products", detail: String(localized: "Built products written outside DerivedData."), rebuild: String(localized: "A rebuild recreates these."))
        ]
    }()

    static let dependencyNames: Set<String> = ["node_modules", "pods", ".venv", "venv", "vendor", "bower_components", "carthage", "target"]
    static let outputNames: Set<String> = ["build", "dist", ".next", ".nuxt", ".svelte-kit", ".turbo", "out", "coverage", "test-results", ".build", "deriveddata", "htmlcov"]
    static let rebuildableNames = dependencyNames.union(outputNames).union(["release", "debug", "bin", "obj"])
    private static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "java", "kt", "kts", "rs", "go", "py", "rb", "php", "cs", "ts", "tsx", "js", "jsx", "vue", "svelte", "sh", "bash", "zsh", "sql", "dart", "ex", "exs", "lua", "r", "scala", "clj", "gradle"]
    private static let buildExtensions: Set<String> = ["o", "obj", "a", "so", "dylib", "class", "pyc", "pyd", "wasm", "map", "d", "tbd", "pdb"]

    static func isSourceFile(_ url: URL) -> Bool { sourceExtensions.contains(url.pathExtension.lowercased()) }
    static func isBuildArtifact(_ url: URL) -> Bool { buildExtensions.contains(url.pathExtension.lowercased()) || ["app", "framework", "dsym", "xcarchive"].contains(url.pathExtension.lowercased()) }

    static func classify(_ url: URL, gitIgnored: Bool? = nil, sourceCheck: Bool = false) -> CleanupEvidence {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent.lowercased()
        if CleanupSafety.isSensitive(path) {
            return CleanupEvidence(kind: .sensitive, detail: String(localized: "Source-control metadata, credentials, or a personal data store."), rebuild: nil, gitIgnored: false)
        }
        let isDirectory = url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory, FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            return CleanupEvidence(kind: .projectRoot, detail: String(localized: "Contains a Git repository. Nuke Sweep refuses to move a project or source root whole."), rebuild: nil, gitIgnored: gitIgnored ?? false)
        }
        if let cache = caches.first(where: { path == $0.prefix || path.hasPrefix($0.prefix + "/") }) {
            return CleanupEvidence(kind: .knownCache, detail: cache.detail, rebuild: cache.rebuild, gitIgnored: gitIgnored ?? false)
        }
        if let archive = archives.first(where: { path == $0.prefix || path.hasPrefix($0.prefix + "/") }) {
            return CleanupEvidence(kind: .buildOutput, detail: archive.detail, rebuild: archive.rebuild, gitIgnored: gitIgnored ?? false)
        }
        if dependencyNames.contains(name) {
            return CleanupEvidence(kind: .dependency, detail: String(localized: "A dependency or package store that can be recreated."), rebuild: rebuildAdvice(for: name), gitIgnored: gitIgnored ?? false)
        }
        if outputNames.contains(name) {
            return CleanupEvidence(kind: .buildOutput, detail: String(localized: "Generated build output. A copied manifest inside does not make it source."), rebuild: rebuildAdvice(for: name), gitIgnored: gitIgnored ?? false)
        }
        if isDirectory, sourceCheck, looksLikeSourceDirectory(url) {
            return CleanupEvidence(kind: .sourceLike, detail: String(localized: "Contains source-like files and no clear build-output signature. Nuke Sweep refuses to move it whole."), rebuild: nil, gitIgnored: gitIgnored ?? false)
        }
        if gitIgnored == true {
            return CleanupEvidence(kind: .gitIgnored, detail: String(localized: "Git reports this path as ignored, which is evidence it is generated."), rebuild: String(localized: "Rebuild or regenerate it from the tracked source."), gitIgnored: true)
        }
        if isDirectory, ReviewPlanner.looksLikeProjectRoot(url) {
            return CleanupEvidence(kind: .projectRoot, detail: String(localized: "Contains project or source markers at its top level. Nuke Sweep refuses to move it whole."), rebuild: nil, gitIgnored: false)
        }
        return CleanupEvidence(kind: .unknown, detail: String(localized: "Nuke Sweep has no reliable evidence about this item. Review it before selecting."), rebuild: nil, gitIgnored: gitIgnored ?? false)
    }

    /// A bounded, conservative source-tree probe. It skips dependency/build names
    /// and treats any compiled artifact as enough build evidence to stop guessing.
    static func looksLikeSourceDirectory(_ root: URL) -> Bool {
        if rebuildableNames.contains(root.lastPathComponent.lowercased()) { return false }
        let deadline = Date().addingTimeInterval(1)
        var visited = 0, source = 0, build = 0
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 2, visited < 800, Date() <= deadline, build == 0 else { return }
            _ = try? DirectoryEntries.visit(dir, shouldContinue: { visited < 800 && Date() <= deadline && build == 0 }) { child in
                visited += 1
                let name = child.lastPathComponent.lowercased()
                guard !rebuildableNames.contains(name), ![".git", ".hg", ".svn"].contains(name) else { return }
                if name.hasSuffix(".app") || name.hasSuffix(".framework") || name.hasSuffix(".dsym") || name.hasSuffix(".xcarchive") { build += 1; return }
                var s = stat()
                guard lstat(child.path, &s) == 0 else { return }
                if s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                    if depth < 2 { walk(child, depth: depth + 1) }
                } else {
                    let ext = child.pathExtension.lowercased()
                    if sourceExtensions.contains(ext) { source += 1 }
                    else if buildExtensions.contains(ext) { build += 1 }
                }
            }
        }
        walk(root, depth: 0)
        return source > 0 && build == 0
    }

    static func repoRoot(for url: URL) -> URL? {
        if case .found(let root) = GitInspection.repository(for: url) { return root }
        return nil
    }

    static func gitTracked(_ url: URL) -> Bool? { GitInspection.inspect(url).tracked }

    static func rebuildAdvice(for name: String) -> String {
        switch name {
        case "node_modules": return "Reinstall with npm, pnpm, yarn, or bun."
        case "pods": return "Run pod install."
        case ".venv", "venv": return "Recreate the virtual environment and reinstall dependencies."
        case "target": return "Run cargo build."
        case "vendor": return "Reinstall dependencies with your package manager."
        case "carthage": return "Run carthage bootstrap."
        case "build", "dist", "out", "coverage", "test-results": return "Rebuild from source."
        case ".next", ".nuxt", ".svelte-kit": return "Rebuild the site or app."
        case ".build", "deriveddata": return "Rebuild with Xcode or SwiftPM."
        default: return "Regenerate it from source."
        }
    }

    /// A bounded git probe used by the review plan, where only selected items are checked.
    static func gitIgnored(_ url: URL) -> Bool? { GitInspection.ignored(url) }
}

struct CleanupPlan: Codable {
    let generatedAt: Date
    let note: String
    let totalLogicalSize: Int64
    let items: [Item]
    let warnings: [String]
    struct Item: Codable {
        let path: String
        let size: Int64
        let directory: Bool
        let evidence: CleanupEvidence?
    }
}
