import Foundation

struct DiskJobSnapshot: Identifiable, Sendable {
    let id: UUID
    let label: String
    let state: String
    let started: Date?
    let path: String
    let visited: Int
    let canStop: Bool
}
@Observable @MainActor final class DiskActivity {
    static let shared = DiskActivity()
    var running = ""
    var waiting = 0
    var path = ""
    var visited = 0
    var started: Date?
    var canStop = false
    var jobs: [DiskJobSnapshot] = []
    func stop() { DiskWork.cancelAll() }
    func stop(_ id: UUID) { DiskWork.cancel(id) }
}
/// Two lanes, each running a few jobs side by side: bulk scans, and short
/// interactive work that must never wait behind a scan. Background priority affects pending bulk work.
enum DiskWork {
    enum Priority: Int { case background = 0, foreground = 1 }
    enum Lane: Hashable { case bulk, interactive }
    /// Sendable because a job is created on one thread and run on a lane's queue.
    /// Its operation is the continuation-resuming closure built in `run`, which
    /// is already required to be `@Sendable` there.
    private struct Job: Sendable {
        let id = UUID()
        let label: String
        let lane: Lane
        let priority: Priority
        let cancellation: ScanCancellation?
        let operation: @Sendable () -> Void
    }
    private struct Progress {
        let started = Date()
        var path = ""
        var visited = 0
        var last = Date.distantPast
    }
    /// Identifies the running job to `report` without parsing a string per call, and carries
    /// that worker's own throttle deadline. One job runs start-to-finish on a single thread,
    /// so `nextReport` is only ever touched by the owning worker and needs no synchronization.
    private final class JobHandle {
        let id: UUID
        var nextReport: UInt64 = 0
        init(id: UUID) { self.id = id }
    }
    private static let lock = NSLock()
    private static let bulkQueue = DispatchQueue(label: "local.nuke.disk.bulk", qos: .utility, attributes: .concurrent)
    private static let interactiveQueue = DispatchQueue(label: "local.nuke.disk.interactive", qos: .userInitiated, attributes: .concurrent)
    private static let threadKey = "local.nuke.disk.job"
    /// At most five progress ticks per second per worker; progress is cosmetic, scans are not.
    private static let reportIntervalNS: UInt64 = 200_000_000
    // Guarded by `lock` without exception: every read and write below happens
    // inside a lock/unlock pair, which the compiler cannot see through. The
    // unsafe opt-out records that invariant rather than hiding its absence.
    nonisolated(unsafe) private static var pending: [Job] = []
    nonisolated(unsafe) private static var active: [Job] = []
    /// How many jobs each lane runs at once. One big scan per lane kept every
    /// other request waiting; a few side by side keeps the app responsive
    /// without thrashing the disk.
    static let width: [Lane: Int] = [.bulk: 2, .interactive: 4]
    nonisolated(unsafe) private static var progress: [UUID: Progress] = [:]

    static func cancelActiveInspection() {
        lock.lock(); let tokens = active.compactMap(\.cancellation); lock.unlock()
        tokens.forEach { $0.cancel() }
        lock.lock(); publish(); lock.unlock()
    }
    /// Jobs that cannot be stopped: they have no cancellation token.
    static func cancelAll() {
        lock.lock(); let tokens = (pending + active).compactMap(\.cancellation); lock.unlock()
        tokens.forEach { $0.cancel() }
        lock.lock(); publish(); lock.unlock()
    }
    static func cancel(_ id: UUID) {
        lock.lock(); let token = (pending + active).first { $0.id == id }?.cancellation; lock.unlock()
        token?.cancel()
        lock.lock(); publish(); lock.unlock()
    }
    /// Progress reporting sits in the innermost scan loops, so rejecting a call must stay
    /// allocation-free and lock-free: the throttle lives on the worker's own handle, the
    /// label is only built once a tick is accepted, and the scheduler lock is never taken
    /// on the reject path. See `reportIntervalNS` for the accepted-tick budget.
    static func report(path: @autoclosure () -> String, visited: Int) {
        guard let handle = Thread.current.threadDictionary[threadKey] as? JobHandle else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= handle.nextReport else { return }
        handle.nextReport = now + reportIntervalNS
        let label = path()
        lock.lock(); defer { lock.unlock() }
        guard var value = progress[handle.id] else { return }
        value.last = Date(); value.path = label; value.visited = visited; progress[handle.id] = value
        publish()
    }
    /// A progress reporter for the job running on this thread, usable from the
    /// worker threads a parallel scan spreads onto. Nil outside a disk job.
    static func reporter() -> (@Sendable (String, Int) -> Void)? {
        guard let handle = Thread.current.threadDictionary[threadKey] as? JobHandle else { return nil }
        let id = handle.id
        return { label, visited in
            lock.lock(); defer { lock.unlock() }
            guard var value = progress[id], Date().timeIntervalSince(value.last) >= 0.2 else { return }
            value.last = Date(); value.path = label; value.visited = visited; progress[id] = value
            publish()
        }
    }
    static func run<T: Sendable>(_ label: String = "Disk inspection", priority: Priority = .foreground, lane: Lane = .bulk, cancellation: ScanCancellation? = nil, _ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let job = Job(label: label, lane: lane, priority: priority, cancellation: cancellation, operation: { continuation.resume(returning: operation()) })
            lock.lock()
            // Opening a page again asks for the same answer again. The older
            // request still waiting is superseded rather than run twice; its
            // caller sees a cancelled result, as it would after Stop.
            if cancellation != nil {
                for old in pending where old.label == label && old.lane == lane && old.cancellation != nil { old.cancellation?.cancel() }
            }
            pending.append(job); schedule(.interactive); schedule(.bulk); publish(); lock.unlock()
        }
    }
    /// Caller holds lock. Each lane is FIFO within priority, up to `width` jobs at once.
    private static func schedule(_ lane: Lane) {
        // A stopped job returns at once, so it never waits for a free slot.
        while let index = pending.firstIndex(where: { $0.lane == lane && $0.cancellation?.cancelled == true }) {
            start(pending.remove(at: index))
        }
        while active.filter({ $0.lane == lane }).count < width[lane, default: 1], let job = next(lane) { start(job) }
    }
    /// Caller holds lock.
    private static func next(_ lane: Lane) -> Job? {
        let indices = pending.indices.filter { pending[$0].lane == lane }
        // A stopped job returns at once, so it goes first: Stop should empty the
        // queue now, not after everything ahead of it has finished.
        guard let index = indices.first(where: { pending[$0].priority == .foreground }) ?? indices.first else { return nil }
        return pending.remove(at: index)
    }
    /// Caller holds lock.
    private static func start(_ job: Job) {
        let lane = job.lane
        active.append(job); progress[job.id] = Progress()
        let queue = lane == .interactive ? interactiveQueue : bulkQueue
        queue.async {
            Thread.current.threadDictionary[threadKey] = JobHandle(id: job.id)
            job.operation()
            Thread.current.threadDictionary.removeObject(forKey: threadKey)
            lock.lock(); active.removeAll { $0.id == job.id }; progress[job.id] = nil; schedule(lane); publish(); lock.unlock()
        }
    }
    /// Caller holds lock; publish immutable snapshots in scheduler order.
    private static func publish() {
        let running = active.filter { $0.lane == .interactive } + active.filter { $0.lane == .bulk }
        let jobs = (running + pending).map { job in
            let value = progress[job.id]
            return DiskJobSnapshot(id: job.id, label: job.label, state: job.cancellation?.cancelled == true ? "Stopping" : value == nil ? "Queued" : "Running", started: value?.started, path: value?.path ?? "", visited: value?.visited ?? 0, canStop: job.cancellation != nil && job.cancellation?.cancelled != true)
        }
        let primary = jobs.first { $0.started != nil }
        let label = running.map(\.label).joined(separator: " · ")
        let waiting = pending.count
        DispatchQueue.main.async {
            let activity = DiskActivity.shared
            activity.jobs = jobs; activity.running = label; activity.waiting = waiting
            activity.path = primary?.path ?? ""; activity.visited = primary?.visited ?? 0
            activity.started = primary?.started; activity.canStop = jobs.contains(where: \.canStop)
        }
    }
}
