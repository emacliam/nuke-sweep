import Foundation
import AppKit

/// A deterministic main-thread latency workload, so "is the UI responsive?" has a
/// mechanical answer instead of a field report.
///
/// Paired with `--measure-ui`, this scans a known tree and pages through the
/// heavy views on a fixed schedule, then quits. Because the steps and their
/// timings are identical run to run, the recorded p95 is comparable across
/// builds and can gate CI. It changes nothing about normal launches: without
/// `--bench-scan` none of this runs.
@MainActor enum LatencyBench {
    private static let scanFlag = "--bench-scan"
    private static let secondsFlag = "--bench-seconds"

    static var isRequested: Bool { root != nil }

    private static var root: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: scanFlag), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1])
    }

    private static var budget: TimeInterval {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: secondsFlag), args.indices.contains(index + 1),
              let value = Double(args[index + 1]), value > 0 else { return 25 }
        return min(value, 300)
    }

    /// Pages chosen because they render the largest view hierarchies: a regression
    /// in list or tree rendering shows up here before it shows up for a user.
    private static let itinerary: [(delay: TimeInterval, step: String)] = [
        (1.0, "scan"),
        (6.0, "files"),
        (9.0, "cleanup"),
        (12.0, "files"),
        (15.0, "rescan"),
        (20.0, "cleanup")
    ]

    /// The workload the original audit reproduced the freeze with: a duplicate
    /// comparison over a large tree, then paging through its results while the
    /// comparison is still publishing. Opt-in with `--bench-duplicates`, because
    /// it needs a fixture built for it and a longer budget.
    private static let duplicateItinerary: [(delay: TimeInterval, step: String)] = [
        (24.0, "duplicates"),
        (30.0, "files"),
        (34.0, "showDuplicates"),
        (44.0, "cleanup"),
        (48.0, "showDuplicates")
    ]
    private static var wantsDuplicates: Bool { ProcessInfo.processInfo.arguments.contains("--bench-duplicates") }

    static func startIfRequested(model: AppModel) {
        guard let root else { return }
        model.scanRoot = root
        for entry in itinerary + (wantsDuplicates ? duplicateItinerary : []) where entry.delay < budget {
            DispatchQueue.main.asyncAfter(deadline: .now() + entry.delay) {
                perform(entry.step, model: model, root: root)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + budget) {
            UIResponsiveness.flush()
            // Give the flush its queue hop before tearing the process down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
    }

    private static func perform(_ step: String, model: AppModel, root: URL) {
        switch step {
        case "scan": model.page = .storage; model.scan(root, force: true)
        case "rescan": model.scan(root, force: true)
        case "files": model.page = .storage
        case "cleanup": model.page = .findSpace
        case "duplicates": model.page = .duplicates; model.features.findDuplicates(rootOverride: root)
        case "showDuplicates": model.page = .duplicates
        default: break
        }
    }
}
