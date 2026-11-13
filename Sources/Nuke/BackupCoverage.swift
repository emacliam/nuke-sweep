import Foundation

/// Whether a copy of this exists anywhere other than where it sits.
///
/// Every other signal in the app answers "what is this?". This one answers the
/// question that actually decides how much care an item deserves: *if removing it
/// turns out to be a mistake, can it come back?*
///
/// Combined with `RebuildCost` it produces the only quadrant that genuinely
/// matters — storage that nothing regenerates **and** nothing has a copy of. A
/// build folder excluded from Time Machine is cheap to lose because a build
/// recreates it. An archive excluded from Time Machine is the only copy in
/// existence, and until now the app presented the two identically.
///
/// Read-only throughout: `tmutil isexcluded` reports configuration, it does not
/// change it, and nothing here enables or alters a backup.
enum BackupCoverage: String, Equatable, Sendable {
    /// Time Machine is configured and this path is not excluded from it. Not a
    /// promise that a backup exists — only that this path is in scope for one.
    case included
    /// Explicitly excluded from Time Machine, so backups will never hold it.
    case excluded
    /// Time Machine is not configured on this Mac at all.
    case noBackupConfigured
    /// The question could not be answered: tmutil missing, timed out, or refused.
    case unknown

    /// True only when the app can positively say a backup will not hold this.
    /// `unknown` deliberately does not count: an unanswered question is never
    /// reported as a missing backup.
    var isUnprotected: Bool { self == .excluded || self == .noBackupConfigured }

    var title: String {
        switch self {
        case .included: return String(localized: "In Time Machine scope")
        case .excluded: return String(localized: "Excluded from Time Machine")
        case .noBackupConfigured: return String(localized: "No Time Machine backup configured")
        case .unknown: return String(localized: "Backup coverage unknown")
        }
    }

    /// What this means for the decision in front of the user.
    var detail: String {
        switch self {
        case .included:
            return String(localized: "Time Machine includes this path, so a recent backup may hold a copy. Verify the backup before relying on it.")
        case .excluded:
            return String(localized: "Time Machine is configured to skip this path. No backup will contain it.")
        case .noBackupConfigured:
            return String(localized: "No Time Machine destination is set up on this Mac, so nothing here is being backed up.")
        case .unknown:
            return String(localized: "Backup coverage could not be determined. Treat this as unknown rather than as backed up.")
        }
    }
}

enum BackupCoverageService {
    /// Cached because `tmutil destinationinfo` is a process spawn and the answer
    /// does not change during a scan. Guarded by its own lock; read from scan
    /// workers on the disk lanes.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedDestination: Bool?

    /// Whether any Time Machine destination is configured. A Mac with no
    /// destination has nothing backed up, which matters more than any
    /// per-path exclusion.
    static func hasDestination(run: (String, [String], TimeInterval) -> CommandResult = runTM) -> Bool? {
        lock.lock()
        if let cachedDestination { lock.unlock(); return cachedDestination }
        lock.unlock()
        let result = run("/usr/bin/tmutil", ["destinationinfo"], 5)
        // `tmutil destinationinfo` exits 0 whether or not anything is configured:
        // with no destination it still succeeds and prints "No destinations
        // configured." So the output decides, not the exit status. A non-zero
        // status means the question failed rather than that the answer is no.
        guard result.status == 0 else { return nil }
        let lowered = result.output.lowercased()
        let answer: Bool?
        if lowered.contains("no destinations") { answer = false }
        else if lowered.contains("destination id") { answer = true }
        else { answer = nil } // Unrecognised output is unknown, not "no backup".
        if let answer { lock.lock(); cachedDestination = answer; lock.unlock() }
        return answer
    }

    /// Coverage for one path. Bounded and read-only.
    static func coverage(
        for url: URL,
        run: (String, [String], TimeInterval) -> CommandResult = runTM
    ) -> BackupCoverage {
        guard let configured = hasDestination(run: run) else { return .unknown }
        guard configured else { return .noBackupConfigured }
        let result = run("/usr/bin/tmutil", ["isexcluded", url.path], 5)
        guard result.status == 0 else { return .unknown }
        // Output is "[Excluded]  /path" or "[Included]  /path".
        if result.output.contains("[Excluded]") { return .excluded }
        if result.output.contains("[Included]") { return .included }
        return .unknown
    }

    /// Resets the destination cache. Used by tests and after the user changes
    /// Time Machine settings outside the app.
    static func forgetCachedDestination() {
        lock.lock(); cachedDestination = nil; lock.unlock()
    }

    private static func runTM(_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> CommandResult {
        CommandRunner.run(executable, arguments, timeout: timeout)
    }
}
