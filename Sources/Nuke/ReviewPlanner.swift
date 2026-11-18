import Foundation
import Darwin

struct ReviewBlockedItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let reason: String
}
/// One item's result, reported the moment it is checked.
enum ReviewStreamEvent: Sendable {
    case verified(DiskItem, CleanupEvidence, warning: String?)
    case blocked(ReviewBlockedItem)
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
    static func prepare(_ items: [DiskItem], scopes: [CleanupScope], token: ScanCancellation = ScanCancellation(), managedCacheRoots: [URL] = CacheRule.all.map(\.url), developerScopes: [DeveloperScope] = [], openFiles: () -> [OpenFileUse] = { FileUseService.snapshot() }, stream: (@Sendable (ReviewStreamEvent) -> Void)? = nil) -> ReviewPreparation {
        // Open files are read once, up front, so each item can be reported
        // complete, warning included, as soon as it is checked.
        let uses = openFiles()
        @Sendable func warning(for item: DiskItem) -> String? {
            let matching = uses.filter { $0.path == item.url.path || (item.directory && $0.path.hasPrefix(item.url.standardizedFileURL.path + "/")) }
            guard !matching.isEmpty else { return nil }
            let apps = Set(matching.map(\.process)).sorted().prefix(4).joined(separator: ", ")
            return "\(item.name) is open in \(apps). Close those apps or builds before continuing."
        }
        // Each item is verified on its own budget and in parallel. One shared
        // 45-second budget, spent item by item, used to run out part way through
        // a large review and mark everything after it as unverified.
        let overall = Date().addingTimeInterval(240)
        let candidates = topLevel(items)
        enum Outcome { case verified(DiskItem, CleanupEvidence), failed(String), cancelled }
        func verify(_ original: DiskItem) -> Outcome {
            // Closing the review stops the items not started yet.
            if token.cancelled { return .cancelled }
            let deadline = min(overall, Date().addingTimeInterval(60))
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
                let sealStart = FSEventsGetCurrentEventId()
                let seal = ReviewSeal.Collector(); seal.observeRoot(original.url)
                if original.directory && !original.symlink {
                    // One parallel read feeds both the seal and the content checks.
                    let state = ReviewWalkState()
                    let rootPath = original.url.path
                    let scan = DiskScanner.scan(original.url, cancellation: token, deadline: deadline, respectIgnored: false, visit: { path, entry in
                        seal.record(path, entry)
                        let name = entry.name
                        if [".git", ".hg", ".svn"].contains(name.lowercased()) && !CleanupSafety.isPackageCache(path) { state.protect(path) }
                        if CleanupSafety.isSensitive(path) { state.protect(path) }
                        guard inspectSource else { return }
                        let relative = path.dropFirst(rootPath.count + 1).split(separator: "/").dropLast()
                        guard !relative.contains(where: { rebuildableNames.contains($0.lowercased()) }) else { return }
                        let child = URL(fileURLWithPath: path)
                        state.note(marker: isProjectMarker(name) ? path : nil,
                                   source: CleanupEvidenceService.isSourceFile(child),
                                   build: CleanupEvidenceService.isBuildArtifact(child))
                    }, reuse: false)
                    let (protected, metadata, sourceCount, buildCount) = state.result()
                    if let protected { throw SafetyError.protectedContents(URL(fileURLWithPath: protected).lastPathComponent) }
                    if metadata != nil { throw SafetyError.projectRoot }
                    if token.cancelled { return .cancelled }
                    if scan.skipped > 0 { throw SafetyError.access(scan.accessIssues.first?.path ?? original.url.path) }
                    guard !scan.limited else { throw SafetyError.budget }
                    if inspectSource, sourceCount > 0, buildCount == 0 { throw SafetyError.sourceLike }
                    guard FileIdentity.read(original.url) == original.identity else { throw CleanupSafety.SafetyError.changed }
                    freshItem = DiskItem(url: original.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: original.modified, identity: original.identity, incomplete: false)
                } else if let current = InventoryService.measure(original.url), current.identity == original.identity { freshItem = current }
                else { throw CleanupSafety.SafetyError.changed }
                let reviewedSeal: String
                if original.directory && !original.symlink {
                    // One read, not two. Anything that changes during or after it
                    // shows in the change record since `sealStart`, which the move
                    // consults; a change there means a full read and compare.
                    reviewedSeal = try seal.finish()
                    freshItem.reviewEventID = sealStart
                } else {
                    reviewedSeal = try ReviewSeal.capture(freshItem, token: token, deadline: deadline)
                    guard try ReviewSeal.capture(freshItem, token: token, deadline: deadline) == reviewedSeal else { throw ReviewSeal.Failure.changed }
                }
                freshItem.reviewSeal = reviewedSeal
                return .verified(freshItem, CleanupEvidenceService.classify(original.url, gitIgnored: ignored))
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        let outcomes = UnsafeMutableBufferPointer<Outcome>.allocate(capacity: max(1, candidates.count))
        defer { outcomes.deallocate() }
        // Three items at a time. Each folder read already spreads across every
        // core; running all items at once made those reads fight over the CPU
        // (43 s on ~/Library/Caches, against 27 s three at a time).
        let next = ReviewCursor()
        DispatchQueue.concurrentPerform(iterations: min(3, max(1, candidates.count))) { _ in
          while let index = next.take(below: candidates.count) {
            let outcome = verify(candidates[index])
            (outcomes.baseAddress! + index).initialize(to: outcome)
            switch outcome {
            case .verified(let item, let found): stream?(.verified(item, found, warning: warning(for: item)))
            case .failed(let reason): stream?(.blocked(.init(url: candidates[index].url, reason: reason)))
            case .cancelled: break
            }
          }
        }
        var fresh: [DiskItem] = [], failures: [String] = [], blocked: [ReviewBlockedItem] = []
        var evidence: [String: CleanupEvidence] = [:], warnings: [String] = []
        for (index, original) in candidates.enumerated() {
            switch outcomes[index] {
            case .verified(let item, let found): fresh.append(item); evidence[original.id] = found
            case .failed(let reason):
                failures.append(original.name + ": " + reason)
                blocked.append(.init(url: original.url, reason: reason))
            case .cancelled: break
            }
        }
        if candidates.count > 0 { (outcomes.baseAddress!).deinitialize(count: candidates.count) }
        warnings = fresh.prefix(24).compactMap(warning(for:))
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

/// What a parallel review walk found, gathered safely from many threads.
final class ReviewWalkState: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var protected: String?
    private var metadata: String?
    private var sourceCount = 0
    private var buildCount = 0
    func protect(_ path: String) { os_unfair_lock_lock(&lock); if protected == nil { protected = path }; os_unfair_lock_unlock(&lock) }
    func note(marker: String?, source: Bool, build: Bool) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        if let marker, metadata == nil { metadata = marker }
        if source { sourceCount += 1 }
        if build { buildCount += 1 }
    }
    func result() -> (String?, String?, Int, Int) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return (protected, metadata, sourceCount, buildCount)
    }
}

/// Hands out item indices to a small pool of review workers.
final class ReviewCursor: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var value = 0
    func take(below count: Int) -> Int? {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard value < count else { return nil }
        defer { value += 1 }
        return value
    }
}
