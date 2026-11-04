import Foundation
import Combine

@MainActor final class DiskActivity: ObservableObject {
    static let shared = DiskActivity()
    @Published var running = ""
    @Published var waiting = 0
    @Published var path = ""
    @Published var visited = 0
    @Published var started: Date?
    @Published var canStop = false
    /// One Stop owns every queued and active disk job, so removing page-level Stops cannot
    /// leave a queued inspection unresponsive.
    func stop() { DiskWork.cancelAll() }
}
/// Priority affects pending jobs; an active traversal finishes or cooperatively cancels first.
enum DiskWork {
    enum Priority: Int { case background = 0, foreground = 1 }
    private struct Job { let label: String; let priority: Priority; let cancellation: ScanCancellation?; let operation: () -> Void }
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "local.nuke.disk", qos: .utility)
    private static var pending: [Job] = []
    private static var active = false
    private static var activeLabel = ""
    private static var activeCancellation: ScanCancellation?
    private static var lastProgress = Date.distantPast
    static func cancelActiveInspection() {
        lock.lock(); let token = activeCancellation; lock.unlock(); token?.cancel()
    }
    static func cancelAll() {
        lock.lock()
        var tokens = pending.compactMap(\.cancellation)
        if let activeCancellation { tokens.append(activeCancellation) }
        lock.unlock()
        var seen = Set<ObjectIdentifier>()
        for token in tokens where seen.insert(ObjectIdentifier(token)).inserted { token.cancel() }
    }
    static func report(path: String, visited: Int) {
        lock.lock()
        guard Date().timeIntervalSince(lastProgress) >= 0.5 else { lock.unlock(); return }
        lastProgress = Date(); lock.unlock()
        DispatchQueue.main.async { DiskActivity.shared.path = path; DiskActivity.shared.visited = visited }
    }
    static func run<T: Sendable>(_ label: String = "Disk inspection", priority: Priority = .foreground, cancellation: ScanCancellation? = nil, _ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            lock.lock()
            pending.append(Job(label: label, priority: priority, cancellation: cancellation, operation: { continuation.resume(returning: operation()) }))
            if !active { active = true; scheduleNext() } else { publish(activeLabel, pending.count); if cancellation != nil { DispatchQueue.main.async { DiskActivity.shared.canStop = true } } }
            lock.unlock()
        }
    }
    /// lock held by caller; FIFO within each priority.
    private static func scheduleNext() {
        guard !pending.isEmpty else { active = false; activeLabel = ""; activeCancellation = nil; publish("", 0); return }
        let index = pending.firstIndex(where: { $0.priority == .foreground }) ?? 0
        let job = pending.remove(at: index)
        activeLabel = job.label; activeCancellation = job.cancellation; lastProgress = .distantPast
        let stoppable = job.cancellation != nil || pending.contains { $0.cancellation != nil }
        DispatchQueue.main.async { DiskActivity.shared.started = Date(); DiskActivity.shared.path = ""; DiskActivity.shared.visited = 0; DiskActivity.shared.canStop = stoppable }
        publish(job.label, pending.count)
        queue.async {
            job.operation()
            lock.lock(); scheduleNext(); lock.unlock()
        }
    }
    private static func publish(_ label: String, _ count: Int) {
        DispatchQueue.main.async { DiskActivity.shared.running = label; DiskActivity.shared.waiting = count }
    }
}
