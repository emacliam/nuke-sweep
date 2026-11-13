import Foundation

/// Watches only the visible folder. Events coalesce; at most one refresh starts per five seconds.
@MainActor final class FolderFreshness {
    private var root: URL?
    private var events: RecursiveChanges?
    private var fallback: Timer?
    private var scheduled: DispatchWorkItem?
    private var generation = UUID()
    private var dirty = false
    private var lastStarted = Date.distantPast
    var canRefresh: () -> Bool = { true }
    var onChange: () -> Void = {}
    var onRefresh: () -> Void = {}
    /// Isolated: the timer and work item below belong to this actor.
    isolated deinit { scheduled?.cancel(); fallback?.invalidate() }
    var available: Bool { events?.available == true }
    func configure(_ url: URL?) {
        let canonical = url?.standardizedFileURL
        guard canonical != root else { return }
        stop(); root = canonical
        guard let canonical else { return }
        let id = generation
        events = RecursiveChanges(canonical) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.changed()
            }
        }
        if !available { fallback = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.changed() } }; fallback?.tolerance = 15 }
    }
    func changed() { guard root != nil else { return }; let alreadyDirty = dirty; dirty = true; if !alreadyDirty { onChange() }; schedule() }
    func finished() { if dirty { schedule() } }
    func cancelPending() { scheduled?.cancel(); scheduled = nil; dirty = false }
    func stop() { fallback?.invalidate(); fallback = nil; cancelPending(); generation = UUID(); events = nil; root = nil }
    private func schedule() {
        guard scheduled == nil else { return }
        let id = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id else { return }; self.scheduled = nil
            guard self.dirty else { return }
            guard self.canRefresh() else { self.schedule(); return }
            self.dirty = false; self.lastStarted = Date(); self.onRefresh()
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2, 5 - Date().timeIntervalSince(lastStarted)), execute: work)
    }
}
