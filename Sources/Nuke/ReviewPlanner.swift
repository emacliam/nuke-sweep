import Foundation
import Darwin

struct ReviewPreparation: Sendable {
    let items: [DiskItem]
    let failures: [String]
    var evidence: [String: CleanupEvidence] = [:]
    var warnings: [String] = []
}
enum ReviewPlanner {
    static func topLevel(_ items: [DiskItem]) -> [DiskItem] {
        var result: [DiskItem] = []
        for item in items.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let path = item.url.standardizedFileURL.path
            if !result.contains(where: { $0.id == item.id || ($0.directory && !$0.symlink && path.hasPrefix($0.url.standardizedFileURL.path + "/")) }) { result.append(item) }
        }
        return result
    }
    /// A cheap last line of defence: a folder that looks like a project or source root
    /// is never moved as a whole, even if it was selected in a cleanup scope.
    static let projectMarkers: Set<String> = [".git", ".hg", ".svn", "package.json", "Package.swift", "Cargo.toml", "go.mod", "pyproject.toml", "Podfile", "composer.json", "Gemfile", "build.gradle", "build.gradle.kts", "pom.xml", "requirements.txt"]
    static let rebuildableNames: Set<String> = ["node_modules", "dist", "build", ".next", "target", ".venv", "venv", "pods", "deriveddata", "coverage", "out", ".build", "test-results"]
    static func looksLikeProjectRoot(_ url: URL) -> Bool {
        let own = url.lastPathComponent.lowercased()
        if own.hasSuffix(".xcodeproj") || own.hasSuffix(".xcworkspace") || own.hasSuffix(".sln") { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.contains { projectMarkers.contains($0) || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".sln") }
    }
    /// Looks several levels below a selected folder for evidence that it contains a
    /// project, without descending into dependency/build stores. Inconclusive results
    /// are treated as unsafe by the caller.
    static func containsProjectMetadata(_ root: URL, token: ScanCancellation, limit: Int = 5_000) -> (found: Bool, complete: Bool) {
        let deadline = Date().addingTimeInterval(2)
        var visited = 0, found = false, complete = true
        let skip: Set<String> = ["node_modules", ".git", ".hg", ".svn", ".venv", "venv", "pods", "carthage", "vendor", "target", "deriveddata", "coverage", ".build", "dist", "build", ".next", "out", "test-results"]
        func walk(_ dir: URL, depth: Int) -> Bool {
            if token.cancelled || Date() > deadline || visited >= limit { complete = false; return false }
            do {
                let done = try DirectoryEntries.visit(dir, shouldContinue: { !found && !token.cancelled && visited < limit && Date() <= deadline }) { child in
                    visited += 1
                    let name = child.lastPathComponent
                    if projectMarkers.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") || name.hasSuffix(".sln") {
                        found = true; return
                    }
                    guard !skip.contains(name.lowercased()) else { return }
                    var s = stat()
                    guard lstat(child.path, &s) == 0, s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { return }
                    guard depth < 4 else { complete = false; return }
                    _ = walk(child, depth: depth + 1)
                }
                if !done { complete = false }
            } catch { complete = false }
            return found
        }
        guard !rebuildableNames.contains(root.lastPathComponent.lowercased()) else { return (false, true) }
        found = walk(root, depth: 0)
        return (found, complete && !token.cancelled && Date() <= deadline)
    }
    static func prepare(_ items: [DiskItem], scopes: [CleanupScope], token: ScanCancellation = ScanCancellation()) -> ReviewPreparation {
        let deadline = Date().addingTimeInterval(45)
        var fresh: [DiskItem] = [], failures: [String] = []
        var evidence: [String: CleanupEvidence] = [:]
        var warnings: [String] = []
        for original in topLevel(items) {
            if token.cancelled { return .init(items: [], failures: ["Review cancelled. No files were moved."]) }
            do {
                try CleanupSafety.validate(original, allowedRoots: scopes)
                guard Date() < deadline, FileIdentity.read(original.url) == original.identity else { throw CleanupSafety.SafetyError.changed }
                if original.directory && !original.symlink {
                    let name = original.url.lastPathComponent.lowercased()
                    let rebuildable = CleanupEvidenceService.rebuildableNames.contains(name)
                    let hasGit = FileManager.default.fileExists(atPath: original.url.appendingPathComponent(".git").path)
                    let ignored = CleanupEvidenceService.gitIgnored(original.url)
                    if let tracked = CleanupEvidenceService.gitTracked(original.url), tracked { throw SafetyError.tracked }
                    if (!rebuildable && ignored != true) || hasGit {
                        if looksLikeProjectRoot(original.url) { throw SafetyError.projectRoot }
                        let metadata = containsProjectMetadata(original.url, token: token)
                        if metadata.found { throw SafetyError.projectRoot }
                        guard metadata.complete else { throw SafetyError.unverified }
                    }
                    if !rebuildable, CleanupEvidenceService.looksLikeSourceDirectory(original.url) { throw SafetyError.sourceLike }
                }
                if original.directory && !original.symlink {
                    let scan = DiskScanner.scan(original.url, cancellation: token, deadline: deadline)
                    guard scan.skipped == 0 && !scan.limited else { throw CleanupSafety.SafetyError.changed }
                    fresh.append(DiskItem(url: original.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: nil, identity: original.identity, incomplete: false))
                } else if let current = InventoryService.measure(original.url) { fresh.append(current) }
                else { throw CleanupSafety.SafetyError.changed }
                let git = evidence.count < 40 ? CleanupEvidenceService.gitIgnored(original.url) : nil
                evidence[original.id] = CleanupEvidenceService.classify(original.url, gitIgnored: git)
            } catch { if failures.count < 20 { failures.append(original.name + ": " + error.localizedDescription) } }
        }
        if failures.isEmpty && !fresh.isEmpty {
            let uses = FileUseService.snapshot()
            for item in fresh.prefix(24) {
                let matching = uses.filter { use in
                    use.path == item.url.path || (item.directory && use.path.hasPrefix(item.url.standardizedFileURL.path + "/"))
                }
                guard !matching.isEmpty else { continue }
                let apps = Set(matching.map(\.process)).sorted().prefix(4).joined(separator: ", ")
                warnings.append("\(item.name) is open in \(apps). Close those apps or builds before continuing.")
            }
        }
        return .init(items: failures.isEmpty ? fresh : [], failures: failures, evidence: failures.isEmpty ? evidence : [:], warnings: failures.isEmpty ? warnings : [])
    }
    enum SafetyError: LocalizedError {
        case projectRoot, sourceLike, tracked, unverified
        var errorDescription: String? {
            switch self {
            case .projectRoot:
                return "Looks like a project or source folder (contains .git or a package manifest). Nuke Sweep will not move it as a whole; open it and select build folders inside."
            case .sourceLike:
                return "Contains source-like files and no clear build-output signature. Nuke Sweep will not move it whole; select a build folder inside."
            case .tracked:
                return "Contains files tracked by git. Nuke Sweep only cleans untracked or generated storage; select an ignored build folder inside."
            case .unverified:
                return "Nuke Sweep could not verify every item in this folder within its safety bounds. Select a narrower folder or resolve access before cleanup."
            }
        }
    }
}
