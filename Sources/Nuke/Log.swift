import Foundation
import OSLog

/// Structured logging for the paths that matter when something goes wrong in the
/// field: scans, cleanup execution, AI requests and the hang watchdog.
///
/// These land in the unified log, which `scripts/capture-hang.sh` already
/// collects — so a hang report arrives with a breadcrumb trail of what the app
/// was doing, instead of only a stack with no history.
///
/// Privacy is explicit, not accidental. `Logger` redacts interpolated strings by
/// default; this file keeps that default and marks a value `.public` only when it
/// cannot identify the user: counts, durations, byte totals, enum cases and
/// provider names. Paths, folder names, item names, search text, model output and
/// anything typed by the user stay private and appear redacted in collected logs.
enum Log {
    private static let subsystem = "com.zyncraft.nukesweep"

    /// Folder measurement, tree listing and duplicate comparison.
    static let scan = Logger(subsystem: subsystem, category: "scan")
    /// Review preparation and the execution of a reviewed cleanup.
    static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    /// Provider requests, cache hits and response rejections.
    static let ai = Logger(subsystem: subsystem, category: "ai")
    /// Main-thread stalls and diagnostics capture.
    static let watchdog = Logger(subsystem: subsystem, category: "watchdog")
    /// Launch, session restore, persistence and termination.
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    /// Folder access denials and permission recovery.
    static let access = Logger(subsystem: subsystem, category: "access")
}
