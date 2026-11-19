import Foundation

/// Keeps what is on screen true while the app is open.
///
/// FSEvents watchers on Trash and on the home folder. Changes are batched
/// (Trash after 1 second, everything else after 3) and only then looked at, so
/// a busy cache folder costs a set insert per event, not a rescan.
@MainActor final class LiveWatch {
    private var trash: RecursiveChanges?
    private var home: RecursiveChanges?
    private var trashPending: DispatchWorkItem?
    private var homePending: DispatchWorkItem?
    private weak var model: AppModel?
    static var lastMeasure = Date.distantPast
    static var lastCaches = Date.distantPast

    func start(_ model: AppModel) {
        guard trash == nil else { return }
        self.model = model
        trash = RecursiveChanges(TrashService.current.root) { [weak self] in
            Task { @MainActor in self?.schedule(trash: true) }
        }
        home = RecursiveChanges(FileManager.default.homeDirectoryForCurrentUser) { [weak self] in
            Task { @MainActor in self?.schedule(trash: false) }
        }
    }

    private func schedule(trash isTrash: Bool) {
        let pending = isTrash ? trashPending : homePending
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if isTrash {
                self.trashPending = nil
                _ = self.trash?.consume()
                self.model?.trashChangedOutside()
            } else {
                self.homePending = nil
                guard let changes = self.home?.consume() else { return }
                self.model?.filesChangedOutside(all: changes.all, paths: changes.paths)
            }
        }
        if isTrash { trashPending = work } else { homePending = work }
        DispatchQueue.main.asyncAfter(deadline: .now() + (isTrash ? 1 : 3), execute: work)
    }
}

extension AppModel {
    /// Trash changed in Finder or elsewhere: refresh what shows it.
    func trashChangedOutside() {
        guard !actionBusy else { return }
        refreshResources()
        if page == .trash || trashSnapshot != nil { inspectTrash() }
        guard quick.trashSize != nil || quick.measured != nil else { return }
        Task {
            let token = ScanCancellation()
            let scan = await DiskWork.run("Measuring Trash", lane: .interactive, cancellation: token) {
                DiskScanner.scan(TrashService.current.root, cancellation: token, deadline: Date().addingTimeInterval(30))
            }
            quick.trashSize = scan.skipped == 0 && !scan.limited ? scan.logical : nil
            quick.trashPartial = scan.skipped > 0 || scan.limited
        }
    }

    /// Something under the home folder changed. If it touches what the check
    /// listed, drop what is gone and re-measure the rest; when sizes moved
    /// noticeably, say so rather than show figures that are no longer true.
    func filesChangedOutside(all: Bool, paths: Set<String>) {
        let record = ScanReuse(remembered: [:], changed: Array(paths))
        func touched(_ url: URL) -> Bool { all || record.dirty(url.standardizedFileURL.path) }
        // Pages that list folders of their own (tool caches, worktrees) decide for themselves.
        NotificationCenter.default.post(name: .nukeFilesChanged, object: nil, userInfo: ["all": all, "paths": paths])
        if showTrashReview && !actionBusy { reviewItemsChanged(pendingTrash.filter { touched($0.url) }) }
        if page == .developer, !cacheScanning, !caches.isEmpty, Date().timeIntervalSince(LiveWatch.lastCaches) > 30,
           caches.contains(where: { touched($0.rule.url) }) {
            LiveWatch.lastCaches = Date()
            scanCaches()
        }
        guard !actionBusy, !fullCheck.running, fullCheckResultIsCurrent else { return }
        let listed = fullCheckItems()
        let affected: [DiskItem]
        if all {
            affected = listed
        } else {
            affected = listed.filter { touched($0.url) }
        }
        guard !affected.isEmpty else { return }
        pruneAfterMutation()
        // Re-measuring is for named changes, at most twice a minute. An
        // overflow ("something changed somewhere") only drops what is gone.
        guard !all, Date().timeIntervalSince(LiveWatch.lastMeasure) > 30 else { return }
        LiveWatch.lastMeasure = Date()
        Task {
            let token = ScanCancellation()
            let drift = await DiskWork.run("Checking changed locations", lane: .interactive, cancellation: token) { () -> Int64 in
                var moved: Int64 = 0
                for item in affected.prefix(40) where !token.cancelled {
                    var info = stat()
                    guard lstat(item.url.path, &info) == 0 else { continue }
                    let now = item.directory ? DiskScanner.scan(item.url, cancellation: token, deadline: Date().addingTimeInterval(10)).logical : Int64(info.st_size)
                    moved += abs(now - item.size)
                }
                return moved
            }
            // Small churn (a browser writing its cache) is not worth a message.
            if drift > 200_000_000 { fullCheck.changedSince = drift }
        }
    }
}

extension Notification.Name {
    /// Posted with `all` (Bool) and `paths` (Set<String>) when watched files change.
    static let nukeFilesChanged = Notification.Name("nuke.filesChanged")
}

extension AppModel {
    /// Items in the open review that changed on disk after their check. Gone
    /// ones leave the list; the rest are unticked and marked until checked again.
    func reviewItemsChanged(_ items: [DiskItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            var info = stat()
            if lstat(item.url.path, &info) != 0 {
                pendingTrash.removeAll { $0.id == item.id }
                pendingTrashSelection.remove(item.id)
                pendingEvidence[item.id] = nil
                pendingChanged.remove(item.id)
            } else {
                pendingChanged.insert(item.id)
                pendingTrashSelection.remove(item.id)
            }
        }
    }

    /// Checks the changed review items again, in the background, and puts back
    /// the ones that pass.
    func recheckChangedReviewItems() {
        let items = pendingTrash.filter { pendingChanged.contains($0.id) }
        guard !items.isEmpty, !actionBusy else { return }
        let scopes = FolderAccess.shared.cleanupScopes
        let developerScopes = features.developerScopes
        let token = ScanCancellation()
        Task {
            let result = await DiskWork.run("Checking changed items again", lane: .interactive, cancellation: token) {
                ReviewPlanner.prepare(items, scopes: scopes, token: token, developerScopes: developerScopes)
            }
            let ids = Set(items.map(\.id))
            pendingTrash.removeAll { ids.contains($0.id) }
            pendingChanged.subtract(ids)
            for item in result.items {
                pendingTrash.append(item)
                pendingTrashSelection.insert(item.id)
                if let evidence = result.evidence[item.id] { pendingEvidence[item.id] = evidence }
            }
            pendingBlocked.append(contentsOf: result.blocked)
        }
    }
}
