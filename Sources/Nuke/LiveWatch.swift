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
        guard !actionBusy, !fullCheck.running, fullCheckResultIsCurrent else { return }
        let listed = fullCheckItems()
        let affected: [DiskItem]
        if all {
            affected = listed
        } else {
            let record = ScanReuse(remembered: [:], changed: Array(paths))
            affected = listed.filter { record.dirty($0.url.standardizedFileURL.path) }
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
