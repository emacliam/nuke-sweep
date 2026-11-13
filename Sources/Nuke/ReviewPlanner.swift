import Foundation
import Darwin

struct ReviewBlockedItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let reason: String
}
struct ReviewPreparation: Sendable {
    let items: [DiskItem]
    let failures: [String]
    var evidence: [String: CleanupEvidence] = [:]
    var warnings: [String] = []
    var blocked: [ReviewBlockedItem] = []
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
    static let projectMarkers: Set<String> = [".git", ".hg", ".svn", "package.json", "Package.swift", "Cargo.toml", "go.mod", "pyproject.toml", "Podfile", "composer.json", "Gemfile", "build.gradle", "build.gradle.kts", "pom.xml", "requirements.txt"]
    static let rebuildableNames = CleanupEvidenceService.rebuildableNames
    static func isProjectMarker(_ name: String) -> Bool {
        projectMarkers.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") || name.hasSuffix(".sln")
    }
    static func looksLikeProjectRoot(_ url: URL) -> Bool {
        let own = url.lastPathComponent.lowercased()
        if own.hasSuffix(".xcodeproj") || own.hasSuffix(".xcworkspace") || own.hasSuffix(".sln") { return true }
        var found = false, count = 0
        let deadline = Date().addingTimeInterval(0.05)
        _ = try? DirectoryEntries.visit(url, shouldContinue: { !found && count < 1_000 && Date() < deadline }) { count += 1; if isProjectMarker($0.lastPathComponent) { found = true } }
        return found
    }
    /// Only built-in cache policy supplies these roots. Folder grants do not turn a
    /// custom source tree into a managed cache. Aliases outside the cache are refused.
    static func isManagedCache(_ url: URL, roots: [URL]) -> Bool {
        let lexical = url.standardizedFileURL.path
        let effective = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { root in
            let base = root.standardizedFileURL.path
            guard lexical == base || lexical.hasPrefix(base + "/") else { return false }
            let resolvedRoot = root.resolvingSymlinksInPath()
            guard resolvedRoot.path == root.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(root.lastPathComponent).path else { return false }
            let expected = resolvedRoot.path + String(lexical.dropFirst(base.count))
            return effective == expected
        }
    }
    /// One complete traversal measures and verifies the selected tree. Nested cache
    /// layouts no longer fail an unrelated four-level metadata probe. Time, entry,
    /// access, cancellation, source-control, and identity guards still fail closed.
    static func prepare(_ items: [DiskItem], scopes: [CleanupScope], token: ScanCancellation = ScanCancellation(), managedCacheRoots: [URL] = CacheRule.all.map(\.url), developerScopes: [DeveloperScope] = [], openFiles: () -> [OpenFileUse] = { FileUseService.snapshot() }) -> ReviewPreparation {
        let deadline = Date().addingTimeInterval(45)
        var fresh: [DiskItem] = [], failures: [String] = [], blocked: [ReviewBlockedItem] = []
        var evidence: [String: CleanupEvidence] = [:], warnings: [String] = []
        for original in topLevel(items) {
            if token.cancelled { return .init(items: [], failures: ["Review cancelled. No files were moved."]) }
            do {
                try CleanupSafety.validate(original, allowedRoots: scopes, developerScopes: developerScopes)
                try EmulatorCleanup.requireAndroidIdle(original.url)
                guard Date() < deadline else { throw SafetyError.budget }
                let managed = isManagedCache(original.url, roots: managedCacheRoots) || EmulatorCleanup.isAndroidSnapshot(original.url)
                let rebuildable = rebuildableNames.contains(original.name.lowercased())
                try GitInspection.inspect(original.url).requireUntracked()
                let ignored = !managed && !rebuildable ? CleanupEvidenceService.gitIgnored(original.url) : nil
                let inspectSource = !managed && !rebuildable && ignored != true
                if inspectSource && isProjectMarker(original.name) { throw SafetyError.projectRoot }
                var freshItem = original
                var seal = ReviewSeal.Builder(); seal.observe(original.url)
                if original.directory && !original.symlink {
                    var metadata: URL?, protected: URL?, sourceCount = 0, buildCount = 0
                    let rootComponents = original.url.standardizedFileURL.pathComponents.count
                    let scan = DiskScanner.scan(original.url, cancellation: token, deadline: deadline, observing: { child in
                        seal.observe(child)
                        let name = child.lastPathComponent
                        if [".git", ".hg", ".svn"].contains(name.lowercased()) { protected = child }
                        if CleanupSafety.isSensitive(child.standardizedFileURL.path) { protected = child }
                        guard inspectSource else { return }
                        let relativeParents = child.deletingLastPathComponent().standardizedFileURL.pathComponents.dropFirst(rootComponents)
                        guard !relativeParents.contains(where: { rebuildableNames.contains($0.lowercased()) }) else { return }
                        if isProjectMarker(name) { metadata = child }
                        if CleanupEvidenceService.isSourceFile(child) { sourceCount += 1 }
                        if CleanupEvidenceService.isBuildArtifact(child) { buildCount += 1 }
                    })
                    if let protected { throw SafetyError.protectedContents(protected.lastPathComponent) }
                    if metadata != nil { throw SafetyError.projectRoot }
                    if token.cancelled { return .init(items: [], failures: ["Review cancelled. No files were moved."]) }
                    if scan.skipped > 0 { throw SafetyError.access(scan.accessIssues.first?.path ?? original.url.path) }
                    guard !scan.limited else { throw SafetyError.budget }
                    if inspectSource, sourceCount > 0, buildCount == 0 { throw SafetyError.sourceLike }
                    guard FileIdentity.read(original.url) == original.identity else { throw CleanupSafety.SafetyError.changed }
                    freshItem = DiskItem(url: original.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: original.modified, identity: original.identity, incomplete: false)
                } else if let current = InventoryService.measure(original.url), current.identity == original.identity { freshItem = current }
                else { throw CleanupSafety.SafetyError.changed }
                let reviewedSeal: String
                if original.directory && !original.symlink { reviewedSeal = try seal.finish() }
                else { reviewedSeal = try ReviewSeal.capture(freshItem, token: token, deadline: deadline) }
                guard try ReviewSeal.capture(freshItem, token: token, deadline: deadline) == reviewedSeal else { throw ReviewSeal.Failure.changed }
                freshItem.reviewSeal = reviewedSeal
                fresh.append(freshItem)
                evidence[original.id] = CleanupEvidenceService.classify(original.url, gitIgnored: ignored)
            } catch {
                let reason = error.localizedDescription
                failures.append(original.name + ": " + reason)
                blocked.append(.init(url: original.url, reason: reason))
            }
        }
        if !fresh.isEmpty {
            let uses = openFiles()
            for item in fresh.prefix(24) {
                let matching = uses.filter { $0.path == item.url.path || (item.directory && $0.path.hasPrefix(item.url.standardizedFileURL.path + "/")) }
                if !matching.isEmpty {
                    let apps = Set(matching.map(\.process)).sorted().prefix(4).joined(separator: ", ")
                    warnings.append("\(item.name) is open in \(apps). Close those apps or builds before continuing.")
                }
            }
        }
        if token.cancelled { return .init(items: [], failures: ["Review cancelled. No files were moved."]) }
        return .init(items: fresh, failures: failures, evidence: evidence, warnings: warnings, blocked: blocked)
    }
    /// Keep cache roots and Xcode project containers, reviewing independently measured children.
    static func prepareCacheContents(_ rule: CacheRule, scopes: [CleanupScope], token: ScanCancellation, developerScopes: [DeveloperScope] = [], openFiles: () -> [OpenFileUse] = { FileUseService.snapshot() }) -> ReviewPreparation {
        let contents = cacheCandidates(at: rule.url, xcodeContainers: rule.url.lastPathComponent == "DerivedData", token: token)
        var result = prepare(contents.items, scopes: scopes, token: token, developerScopes: developerScopes, openFiles: openFiles)
        result.blocked += contents.blocked
        if contents.items.isEmpty && contents.blocked.isEmpty { return .init(items: [], failures: ["No cache contents were found. No files were moved."]) }
        return result
    }
    /// Prepare a bounded batch of immediate children of a generated folder.
    /// The container stays in place. Each child goes through normal review.
    static func prepareFolderContents(_ folder: DiskItem, scopes: [CleanupScope], token: ScanCancellation,
                                      developerScopes: [DeveloperScope] = [],
                                      openFiles: () -> [OpenFileUse] = { FileUseService.snapshot() }) -> ReviewPreparation {
        guard !token.cancelled else { return .init(items: [], failures: ["Review cancelled. No files were moved."]) }
        var info = stat()
        guard folder.directory, !folder.symlink, let identity = folder.identity,
              lstat(folder.url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)) == identity else {
            return .init(items: [], failures: ["This folder changed since the scan. Refresh it and try again."])
        }
        let evidence = CleanupEvidenceService.classify(folder.url, sourceCheck: true)
        guard evidence.kind.supportsContentsReview else {
            return .init(items: [], failures: ["Contents review is available for known caches, dependency folders, and build output. Browse this folder to select items individually."])
        }
        let contents = cacheCandidates(at: folder.url, xcodeContainers: false, token: token)
        guard FileIdentity.read(folder.url) == identity else {
            return .init(items: [], failures: ["This folder changed during review. Refresh it and try again."])
        }
        guard !contents.items.isEmpty || !contents.blocked.isEmpty else {
            return .init(items: [], failures: ["There are no items to review in this folder."])
        }
        var result = prepare(contents.items, scopes: scopes, token: token, developerScopes: developerScopes, openFiles: openFiles)
        result.blocked += contents.blocked
        return result
    }

    static func cacheCandidates(at root: URL, xcodeContainers: Bool, token: ScanCancellation) -> (items: [DiskItem], blocked: [ReviewBlockedItem]) {
        var candidates: [DiskItem] = [], blocked: [ReviewBlockedItem] = [], count = 0
        let deadline = Date().addingTimeInterval(15)
        func collect(_ root: URL, expandXcode: Bool) {
            do {
                let complete = try DirectoryEntries.visit(root, shouldContinue: { !token.cancelled && Date() < deadline && count < 500 }) { child in
                    count += 1
                    var info = stat()
                    guard lstat(child.path, &info) == 0 else { blocked.append(.init(url: child, reason: "Could not read this item. Check folder access.")); return }
                    let directory = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
                    if expandXcode && directory { collect(child, expandXcode: false); return }
                    candidates.append(DiskItem(url: child, size: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, directory: directory, symlink: info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK), modified: nil, identity: .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), incomplete: false))
                }
                if !complete { blocked.append(.init(url: root, reason: "Listing stopped at its limit. Browse this folder for remaining items.")) }
            } catch { blocked.append(.init(url: root, reason: "Could not list contents: " + error.localizedDescription)) }
        }
        collect(root, expandXcode: xcodeContainers)
        return (candidates, blocked)
    }
    enum SafetyError: LocalizedError {
        case projectRoot, sourceLike, tracked, gitUnavailable, budget, access(String), protectedContents(String)
        var errorDescription: String? {
            switch self {
            case .projectRoot: return "Looks like a project or source folder (contains a package manifest or project file). Open it and select generated folders inside."
            case .sourceLike: return "Contains source-like files and no clear build-output signature. Select a build folder inside."
            case .tracked: return "Contains files tracked by git. Select untracked or generated storage instead."
            case .gitUnavailable: return "Could not verify Git tracking. Check repository access and review again."
            case .budget: return "The complete review reached its time or file limit. Browse this folder and select smaller children; no unverified contents will be moved."
            case .access(let path): return "Could not read \(path). Resolve its access or select readable children, then review again."
            case .protectedContents(let name): return "Contains a project or source folder with protected source-control or personal data (\(name)). Open the folder and select generated children outside it."
            }
        }
    }
}
