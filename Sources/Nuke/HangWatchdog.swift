import Foundation
import AppKit

/// Opt-in, local-only hang capture. The monitor runs on a background queue and pings the main
/// queue at a bounded interval. When the main thread exceeds the stall threshold, it writes a
/// metadata report and a `sample` of this process to Application Support. No network, no upload.
enum HangWatchdog {
    private static let queue = DispatchQueue(label: "local.nuke.hang-watchdog", qos: .utility)
    // Confined to `queue`: every mutation below runs inside a `queue.async`
    // block, so these are serial despite being static. The opt-out records that
    // confinement, which the compiler cannot infer from a DispatchQueue.
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var enabled = false
    nonisolated(unsafe) private static var pending = false
    nonisolated(unsafe) private static var stalledSince = Date()
    nonisolated(unsafe) private static var lastReport = Date.distantPast
    private static var threshold: TimeInterval { AppEnvironment.isDevelopment ? 0.5 : 2 }

    static var directory: URL {
        AppEnvironment.supportRoot.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "nuke.hangDiagnostics")
        queue.async { value ? startOnQueue() : stopOnQueue() }
    }

    static func startIfEnabled() {
        guard AppEnvironment.isDevelopment || UserDefaults.standard.bool(forKey: "nuke.hangDiagnostics") else { return }
        queue.async { startOnQueue() }
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private static func startOnQueue() {
        guard timer == nil, !enabled else { return }
        enabled = true
        pending = false
        stalledSince = Date()
        let source = DispatchSource.makeTimerSource(queue: queue)
        if AppEnvironment.isDevelopment {
            source.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
        } else {
            source.schedule(deadline: .now() + 2, repeating: .seconds(1), leeway: .milliseconds(200))
        }
        source.setEventHandler { ping() }
        timer = source
        source.resume()
    }

    private static func stopOnQueue() {
        enabled = false
        timer?.cancel()
        timer = nil
        pending = false
    }

    private static func ping() {
        guard enabled else { return }
        if pending {
            guard Date().timeIntervalSince(stalledSince) >= threshold,
                  Date().timeIntervalSince(lastReport) >= 30 else { return }
            lastReport = Date()
            Log.watchdog.error("Main thread stalled for \(Date().timeIntervalSince(stalledSince), format: .fixed(precision: 2), privacy: .public)s; capturing a sample")
            capture()
            pending = false
            return
        }
        pending = true
        stalledSince = Date()
        DispatchQueue.main.async {
            queue.async { pending = false }
        }
    }

    private static func capture() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = directory.appendingPathComponent("Hang-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let metadata: [String: Any] = [
            "captured_at": ISO8601DateFormatter().string(from: Date()),
            "uptime_ns": DispatchTime.now().uptimeNanoseconds,
            "version": version,
            "build": build,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "stalled_for_seconds": Date().timeIntervalSince(stalledSince),
            "threshold_seconds": threshold,
            "note": "Main thread did not answer the watchdog before the threshold. Check sample.txt for stack evidence."
        ]
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            let report = folder.appendingPathComponent("metadata.json")
            try? data.write(to: report, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: report.path)
        }
        let sample = folder.appendingPathComponent("sample.txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), AppEnvironment.isDevelopment ? "1" : "3", "-file", sample.path]
        do {
            try process.run()
            process.waitUntilExit()
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sample.path)
        } catch {
            try? Data(("Could not run sample: " + error.localizedDescription + "\n").utf8).write(to: sample)
        }
        pruneOldReports()
    }

    private static func pruneOldReports() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let reports = entries.filter { $0.lastPathComponent.hasPrefix("Hang-") }.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for old in reports.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
    }
}
