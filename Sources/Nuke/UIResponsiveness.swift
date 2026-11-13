import Foundation

/// Local diagnostic for development builds and explicitly instrumented launches.
enum UIResponsiveness {
    enum Phase: String {
        case launch
        case folderPickerRequested, folderPickerOpened, folderPickerReturned
        case scanQueued, scanStarted, scanReturned, scanPublished
        case treeListingQueued, treeListingPublished
    }

    // Confined to `queue`, as in HangWatchdog: the recorder's state is only
    // touched from its own serial queue, including from the timer handler.
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "local.nuke.responsiveness", qos: .utility)
    private static let pending = DispatchSemaphore(value: 1)
    private static let destination: URL? = {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--measure-ui"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1])
        }
        guard AppEnvironment.isDevelopment else { return nil }
        return AppEnvironment.supportRoot.appendingPathComponent("ui-responsiveness.json")
    }()
    nonisolated(unsafe) private static var events: [PhaseMark] = []
    // Recorder state, confined to `queue` like `events`. Held statically rather
    // than captured as locals so the timer handler is not mutating variables it
    // closed over from another isolation domain.
    nonisolated(unsafe) private static var samples: [Double] = []
    nonisolated(unsafe) private static var slow: [[String: Any]] = []
    nonisolated(unsafe) private static var lastWrite: UInt64 = 0

    /// A typed phase mark rather than a dictionary: the recorder hands these to
    /// its own queue, and an untyped `[String: Any]` cannot cross that boundary
    /// safely. Serialised to the same JSON shape on write.
    private struct PhaseMark: Sendable {
        let phase: String
        let uptimeNS: UInt64
        var json: [String: Any] { ["phase": phase, "uptime_ns": uptimeNS] }
    }

    static func mark(_ phase: Phase) {
        guard destination != nil else { return }
        let event = PhaseMark(phase: phase.rawValue, uptimeNS: DispatchTime.now().uptimeNanoseconds)
        queue.async {
            events.append(event)
            if events.count > 128 { events.removeFirst() }
        }
    }

    /// Writes the recording immediately. The periodic write is on a one-second
    /// cadence, so a process that exits on cue would otherwise drop its tail --
    /// exactly the part a bench run cares about.
    static func flush() {
        guard destination != nil else { return }
        queue.sync { latestReport?() }
    }
    nonisolated(unsafe) private static var latestReport: (@Sendable () -> Void)?

    static func startIfRequested() {
        guard let destination, timer == nil else { return }
        if AppEnvironment.isDevelopment {
            try? FileManager.default.createDirectory(at: AppEnvironment.supportRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        mark(.launch)

        // Shared by the periodic write and by `flush`, so a forced write produces
        // exactly the same document as a scheduled one. Always called on `queue`.
        let write: @Sendable () -> Void = {
            guard !samples.isEmpty else { return }
            let sorted = samples.sorted()
            let report: [String: Any] = [
                "samples": samples.count, "max_ms": sorted.last ?? 0,
                "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)],
                "over_250ms": samples.filter { $0 > 250 }.count,
                "slow_samples": slow, "phases": events.map(\.json),
                "pid": ProcessInfo.processInfo.processIdentifier
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        latestReport = write

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
        source.setEventHandler {
            guard pending.wait(timeout: .now()) == .success else { return }
            let start = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                let end = DispatchTime.now().uptimeNanoseconds
                let elapsed = Double(end - start) / 1_000_000
                queue.async {
                    pending.signal()
                    samples.append(elapsed)
                    if samples.count > 6000 { samples.removeFirst(1000) }
                    if elapsed > 250 {
                        slow.append(["start_uptime_ns": start, "end_uptime_ns": end, "latency_ms": elapsed])
                        if slow.count > 32 { slow.removeFirst() }
                    }
                    guard end - lastWrite >= 1_000_000_000 || elapsed > 250 else { return }
                    lastWrite = end
                    write()
                }
            }
        }
        timer = source
        source.resume()
    }
}
