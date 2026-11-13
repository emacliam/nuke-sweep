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
/// Bulk traversal stays serialized; short interactive listings have their own
/// bounded worker so an active scan cannot hold navigation hostage. At most two
/// disk jobs run simultaneously. Background priority affects pending bulk work.
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
    private static let bulkQueue = DispatchQueue(label: "local.nuke.disk.bulk", qos: .utility)
    private static let interactiveQueue = DispatchQueue(label: "local.nuke.disk.interactive", qos: .userInitiated)
    private static let threadKey = "local.nuke.disk.job"
    /// At most five progress ticks per second per worker; progress is cosmetic, scans are not.
    private static let reportIntervalNS: UInt64 = 200_000_000
    // Guarded by `lock` without exception: every read and write below happens
    // inside a lock/unlock pair, which the compiler cannot see through. The
    // unsafe opt-out records that invariant rather than hiding its absence.
    nonisolated(unsafe) private static var pending: [Job] = []
    nonisolated(unsafe) private static var active: [Lane: Job] = [:]
    nonisolated(unsafe) private static var progress: [UUID: Progress] = [:]

    static func cancelActiveInspection() {
        lock.lock(); let tokens = active.values.compactMap(\.cancellation); lock.unlock()
        tokens.forEach { $0.cancel() }
        lock.lock(); publish(); lock.unlock()
    }
    static func cancelAll() {
        lock.lock(); let tokens = (pending + Array(active.values)).compactMap(\.cancellation); lock.unlock()
        tokens.forEach { $0.cancel() }
        lock.lock(); publish(); lock.unlock()
    }
    static func cancel(_ id: UUID) {
        lock.lock(); let token = (pending + Array(active.values)).first { $0.id == id }?.cancellation; lock.unlock()
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
    static func run<T: Sendable>(_ label: String = "Disk inspection", priority: Priority = .foreground, lane: Lane = .bulk, cancellation: ScanCancellation? = nil, _ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let job = Job(label: label, lane: lane, priority: priority, cancellation: cancellation, operation: { continuation.resume(returning: operation()) })
            lock.lock(); pending.append(job); schedule(.interactive); schedule(.bulk); publish(); lock.unlock()
        }
    }
    /// Caller holds lock. Each lane is FIFO within priority, with one active job.
    private static func schedule(_ lane: Lane) {
        guard active[lane] == nil else { return }
        let indices = pending.indices.filter { pending[$0].lane == lane }
        guard let index = indices.first(where: { pending[$0].priority == .foreground }) ?? indices.first else { return }
        let job = pending.remove(at: index)
        active[lane] = job; progress[job.id] = Progress()
        let queue = lane == .interactive ? interactiveQueue : bulkQueue
        queue.async {
            Thread.current.threadDictionary[threadKey] = JobHandle(id: job.id)
            job.operation()
            Thread.current.threadDictionary.removeObject(forKey: threadKey)
            lock.lock(); active[lane] = nil; progress[job.id] = nil; schedule(lane); publish(); lock.unlock()
        }
    }
    /// Caller holds lock; publish immutable snapshots in scheduler order.
    private static func publish() {
        let running = [active[.interactive], active[.bulk]].compactMap { $0 }
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
