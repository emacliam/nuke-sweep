import Foundation
import AppKit

/// The one place the app acts without a person confirming each item.
///
/// Everything else in Nuke Sweep stops at a review. That makes it safe and also
/// makes it a tool someone has to remember to open: the weekly check can say
/// 30 GB has built up again, and nothing happens until they come back and click.
/// This closes that loop for the narrow set of things that cost nothing but a
/// rebuild.
///
/// The rules are deliberately stricter than what a person may select by hand:
///
/// - Off unless switched on, and only ever runs after an automatic check.
/// - Only items positively identified as a cache, dependency folder or build
///   output, with no caution attached (`StorageTriage.Report.unattended`).
/// - Only items untouched, by read or write, for the chosen number of days. An
///   item with no usable date is never eligible.
/// - Every item still passes the same review preparation and the same checks at
///   the moment it moves as a hand-picked one does.
/// - Items go to Trash with a receipt that can put them back. Nothing is
///   permanently deleted and Trash is never emptied.
enum AutoClean {
    private static let enabledKey = "nuke.autoClean.enabled"
    private static let idleKey = "nuke.autoClean.idleDays"
    static let idleChoices = [30, 90, 180]
    static let defaultIdleDays = 90

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var idleDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: idleKey)
            return idleChoices.contains(stored) ? stored : defaultIdleDays
        }
        set { UserDefaults.standard.set(idleChoices.contains(newValue) ? newValue : defaultIdleDays, forKey: idleKey) }
    }

    /// What an unattended run may take from a ranked report.
    static func eligible(_ report: StorageTriage.Report, idleDays: Int, now: Date = Date()) -> [DiskItem] {
        // A threshold below the shortest offered choice would defeat the point of
        // waiting, so a corrupt or hand-edited preference cannot lower it.
        let days = max(idleDays, idleChoices.min() ?? defaultIdleDays)
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return report.unattended.filter { item in
            guard let touched = item.lastTouched else { return false }
            return touched <= cutoff && item.size > 0 && !item.incomplete && !item.symlink
        }
    }

    /// Drops anything review preparation flagged as open in a running app. A
    /// person sees that warning and can close the app; an unattended run cannot.
    static func withoutWarned(_ items: [DiskItem], warnings: [String]) -> [DiskItem] {
        guard !warnings.isEmpty else { return items }
        return items.filter { item in !warnings.contains { $0.hasPrefix(item.name + " is open in") } }
    }
}

struct AutoCleanOutcome: Equatable, Sendable {
    let movedBytes: Int64
    let movedCount: Int
    let failedCount: Int
    let idleDays: Int
}

extension AppModel {
    /// Runs after an automatic check. Returns nil when nothing was attempted.
    func runAutoClean(_ report: StorageTriage.Report) async -> AutoCleanOutcome? {
        guard AutoClean.enabled, FullCheckHistory.weeklyEnabled, fullCheck.automatic else { return nil }
        guard TrialAccess.status().permitsCleanup else { return nil }
        // Never under a person's hands: if a review is open or anything else is
        // changing files, this run is skipped and the next check tries again.
        guard !actionBusy, !showTrashReview, pendingTrash.isEmpty, !reviewPreparing else { return nil }
        let idleDays = AutoClean.idleDays
        let candidates = AutoClean.eligible(report, idleDays: idleDays)
        guard !candidates.isEmpty else { return nil }
        actionBusy = true
        defer { actionBusy = false }
        let scopes = FolderAccess.shared.cleanupScopes
        let developerScopes = features.developerScopes
        let token = ScanCancellation()
        let preparation = await DiskWork.run("Preparing automatic cleanup", cancellation: token) {
            ReviewPlanner.prepare(candidates, scopes: scopes, token: token, developerScopes: developerScopes)
        }
        // Preparation re-measures and re-classifies. Only what it still allows,
        // was asked for, and carries no open-file warning goes any further.
        let asked = Set(candidates.map(\.id))
        let items = AutoClean.withoutWarned(preparation.items.filter { asked.contains($0.id) }, warnings: preparation.warnings)
        guard !items.isEmpty else {
            Log.cleanup.notice("Automatic cleanup: nothing passed review preparation (candidates=\(candidates.count, privacy: .public))")
            return nil
        }
        guard TrialAccess.status().permitsCleanup else { return nil }
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        Log.cleanup.notice("Automatic cleanup executing: items=\(items.count, privacy: .public) idleDays=\(idleDays, privacy: .public)")
        let moved = await DiskWork.run("Automatic cleanup") {
            ReceiptService.moveToTrash(items, proofs: [], runningAppPaths: running, allowedRoots: scopes, developerScopes: developerScopes)
        }
        let receipt = CleanupReceipt(
            date: moved.date,
            title: "Automatic cleanup",
            items: moved.items,
            freeBefore: moved.freeBefore,
            freeAfter: moved.freeAfter,
            undo: "These were moved by the automatic cleanup you switched on: caches, dependencies and build output untouched for \(idleDays) days. " + moved.undo
        )
        features.receipt(receipt)
        let succeeded = receipt.items.filter(\.success)
        let outcome = AutoCleanOutcome(
            movedBytes: succeeded.reduce(0) { $0 + $1.size },
            movedCount: succeeded.count,
            failedCount: receipt.items.count - succeeded.count,
            idleDays: idleDays
        )
        Log.cleanup.notice("Automatic cleanup finished: moved=\(outcome.movedCount, privacy: .public) failed=\(outcome.failedCount, privacy: .public)")
        record("Automatic cleanup", detail: receipt.items.map { "\($0.success ? "Moved to Trash" : "Failed"): \($0.originalPath) · \($0.outcome)" }.joined(separator: "\n"))
        cleanupBasket.removeMoved(succeeded.map(\.originalPath))
        guard outcome.movedCount > 0 else { return outcome }
        AlertCenter.shared.post(
            key: "autoclean",
            title: String(format: String(localized: "Moved %@ to Trash automatically"), bytes(outcome.movedBytes)),
            detail: String(format: String(localized: "%lld locations that rebuild themselves and were untouched for %lld days. The receipt in Nuke Sweep can put each one back. Space returns when Trash is emptied."), outcome.movedCount, idleDays),
            enabled: true
        )
        return outcome
    }

    func setAutoClean(_ enabled: Bool) {
        AutoClean.enabled = enabled
        autoCleanEnabled = enabled
        Log.cleanup.notice("Automatic cleanup preference: enabled=\(enabled, privacy: .public)")
    }

    func setAutoCleanIdleDays(_ days: Int) {
        AutoClean.idleDays = days
        autoCleanIdleDays = AutoClean.idleDays
    }
}
