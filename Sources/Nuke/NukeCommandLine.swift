import Foundation

@MainActor enum NukeCommandLine {
    static let commands: Set<String> = ["check", "clean", "--help", "-h"]

    private struct CheckResult: Encodable {
        let candidateBytes: Int64
        let regenerableBytes: Int64
        let personalFileBytes: Int64
        let heldBackBytes: Int64
        let partiallyMeasuredLocations: Int
        let personalFilesLimited: Bool
        let personalUnreadableLocations: Int
        let projectsMeasured: Bool
    }

    private static let usage = """
    Usage:
      nuke check [--json]   Measure cleanup candidates and personal files.
      nuke clean --review   Prepare a review of rebuildable items.

    Both commands leave files in place. Use Nuke Sweep to confirm any cleanup.
    """

    static func run(_ arguments: [String]) async -> Int32 {
        switch arguments {
        case ["--help"], ["-h"], ["check", "--help"], ["clean", "--help"]:
            print(usage)
            return 0
        case ["check"], ["check", "--json"], ["clean", "--review"]:
            break
        default:
            error(usage)
            return 64
        }

        let model = AppModel(restoring: false)
        guard model.startFullCheck(recordHistory: false) else {
            error("Could not start the storage check.")
            return 1
        }
        if isatty(STDERR_FILENO) == 1 { error("Checking this Mac… Press Control-C to stop.") }
        while model.fullCheck.running {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard model.fullCheckResultIsCurrent, let report = model.triage.report else {
            error("The storage check did not produce a result.")
            return 1
        }

        if arguments == ["clean", "--review"] {
            guard !report.regenerable.isEmpty else {
                print("No rebuildable items found for review.")
                return 0
            }
            let scopes = FolderAccess.shared.cleanupScopes
            let developerScopes = model.features.developerScopes
            if isatty(STDERR_FILENO) == 1 { error("Checking which locations qualify for cleanup…") }
            let review = await DiskWork.run("Preparing cleanup review") {
                ReviewPlanner.prepare(report.regenerable, scopes: scopes, developerScopes: developerScopes)
            }
            print("Eligible locations (\(review.items.count)):")
            for item in review.items {
                print("  \(bytes(item.size))  \(String(reflecting: item.url.path))")
            }
            for item in review.blocked {
                print("  Held back: \(String(reflecting: item.url.path)) — \(String(reflecting: item.reason))")
            }
            for warning in review.warnings { print("  \(String(reflecting: warning))") }
            if review.items.isEmpty {
                for failure in review.failures { error(String(reflecting: failure)) }
            }
            print("Review only. Open Nuke Sweep to confirm cleanup.")
            return review.items.isEmpty ? 1 : 0
        }

        let result = CheckResult(
            candidateBytes: report.totals.candidateBytes,
            regenerableBytes: report.totals.regenerableBytes,
            personalFileBytes: model.personal.report?.totalBytes ?? 0,
            heldBackBytes: report.totals.exposedBytes,
            partiallyMeasuredLocations: model.fullCheck.gaps,
            personalFilesLimited: model.personal.report?.limited ?? false,
            personalUnreadableLocations: model.personal.report?.unreadable.count ?? 0,
            projectsMeasured: !model.fullCheck.projectsSkipped
        )
        if arguments.contains("--json") {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            } catch {
                Self.error("Could not encode the storage check result.")
                return 1
            }
        } else {
            print("\(bytes(result.candidateBytes)) to review, including \(bytes(result.regenerableBytes)) that rebuilds.")
            print("\(bytes(result.personalFileBytes)) in personal files. \(bytes(result.heldBackBytes)) held back.")
            if result.partiallyMeasuredLocations > 0 || result.personalFilesLimited || result.personalUnreadableLocations > 0 {
                print("Some locations could only be measured in part.")
            }
            if !result.projectsMeasured { print("Project build output was not measured.") }
        }
        return 0
    }

    private static func error(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
