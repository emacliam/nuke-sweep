import Foundation

/// What it costs to get something back.
///
/// Size alone cannot answer the question a developer actually asks, which is not
/// "how big is this?" but "is clearing it worth the wait?". 20 GB that returns
/// after one `npm install` is a different proposition from 2 GB that nothing
/// regenerates, and a size-sorted list presents them identically.
///
/// These are deliberately coarse bands, not predictions. The app cannot know the
/// user's network, machine or project size, so it states an order of magnitude
/// and says that it is an estimate. Being vague and honest is more useful here
/// than being precise and wrong.
struct RebuildCost: Equatable, Sendable {
    enum Effort: Int, Comparable, Sendable {
        /// Regenerated on demand, fast enough not to think about.
        case trivial = 0
        /// A short wait: a cache warms again as you work.
        case quick = 1
        /// A deliberate wait: a full dependency install or clean build.
        case slow = 2
        /// Nothing regenerates this. Removing it loses the only copy.
        case irreplaceable = 3
        /// Not enough evidence to say.
        case unknown = 4

        static func < (a: Effort, b: Effort) -> Bool { a.rawValue < b.rawValue }
    }

    let effort: Effort
    /// Phrased as a range, because it is one.
    let estimate: String
    /// The command or action that brings it back, when there is one.
    let action: String?

    var summary: String {
        switch effort {
        case .irreplaceable: return estimate
        case .unknown: return estimate
        default: return "Back in " + estimate + (action.map { " · " + $0 } ?? "")
        }
    }

    static let unknown = RebuildCost(effort: .unknown, estimate: String(localized: "Recovery cost unknown"), action: nil)

    /// The catalogue identifier whose location contains this path, if any.
    private static func catalogued(_ url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for rule in CacheRule.all {
            let base = home + "/" + rule.relativePath
            if path == base || path.hasPrefix(base + "/") { return rule.id }
        }
        // Archives and device support are evidenced by CleanupEvidenceService but
        // are not CacheRule entries, so they are matched explicitly.
        let archives = home + "/Library/Developer/Xcode/Archives"
        if path == archives || path.hasPrefix(archives + "/") { return "archives" }
        return nil
    }

    /// Keyed on the built-in cache identifiers so the Developer list can show a
    /// cost beside every row it already knows how to measure.
    static func forCacheRule(_ id: String) -> RebuildCost {
        switch id {
        case "xcode":
            return .init(effort: .slow, estimate: String(localized: "minutes per project"), action: String(localized: "Xcode rebuilds on next build"))
        case "npm", "pnpm", "yarn", "bun":
            return .init(effort: .quick, estimate: String(localized: "seconds to minutes"), action: String(localized: "re-downloaded on next install"))
        case "pip", "uv", "poetry":
            return .init(effort: .quick, estimate: String(localized: "seconds to minutes"), action: String(localized: "re-downloaded on next install"))
        case "gradle", "maven", "nuget":
            return .init(effort: .slow, estimate: String(localized: "minutes"), action: String(localized: "re-downloaded on next build"))
        case "go", "swiftpm", "cargo":
            return .init(effort: .quick, estimate: String(localized: "under a minute"), action: String(localized: "repopulated by the next build"))
        case "homebrew":
            return .init(effort: .quick, estimate: String(localized: "seconds"), action: String(localized: "re-downloaded only if reinstalling"))
        case "cocoapods":
            return .init(effort: .slow, estimate: String(localized: "minutes"), action: String(localized: "pod install downloads again"))
        case "huggingface", "models":
            return .init(effort: .slow, estimate: String(localized: "minutes to hours"), action: String(localized: "re-downloaded over the network"))
        case "simulator", "devicesupport":
            return .init(effort: .quick, estimate: String(localized: "minutes on next device connect"), action: String(localized: "Xcode re-fetches symbols"))
        case "archives":
            return .init(effort: .irreplaceable, estimate: String(localized: "Not regenerated — only a new archive build replaces it"), action: nil)
        default:
            return .unknown
        }
    }

    /// Derived from local evidence when the caller has no rule in hand.
    ///
    /// Tries the catalogue first by path, because that is where irreplaceability
    /// is recorded: an Xcode archive classifies as build output like any other
    /// generated folder, so judging it by evidence kind alone would lose the one
    /// fact that matters about it. Falls back to the folder name, then to the
    /// evidence kind.
    static func forEvidence(_ evidence: CleanupEvidence?, name: String, url: URL? = nil) -> RebuildCost {
        if let url, let rule = catalogued(url) {
            let cost = forCacheRule(rule)
            if cost.effort != .unknown { return cost }
        }
        let lowered = name.lowercased()
        if lowered == "archives" {
            return forCacheRule("archives")
        }
        if lowered == "node_modules" {
            return .init(effort: .slow, estimate: String(localized: "1–5 minutes"), action: String(localized: "npm/pnpm/yarn install"))
        }
        if lowered == "pods" {
            return .init(effort: .slow, estimate: String(localized: "1–5 minutes"), action: String(localized: "pod install"))
        }
        if lowered == ".venv" || lowered == "venv" {
            return .init(effort: .slow, estimate: String(localized: "1–5 minutes"), action: String(localized: "recreate and reinstall"))
        }
        if lowered == "target" {
            return .init(effort: .slow, estimate: String(localized: "minutes"), action: String(localized: "cargo build"))
        }
        if lowered == "deriveddata" || lowered == ".build" {
            return .init(effort: .slow, estimate: String(localized: "minutes per project"), action: String(localized: "next build"))
        }
        if CleanupEvidenceService.outputNames.contains(lowered) {
            return .init(effort: .slow, estimate: String(localized: "one build"), action: String(localized: "rebuild from source"))
        }
        switch evidence?.kind {
        case .knownCache:
            return .init(effort: .quick, estimate: String(localized: "seconds to minutes"), action: evidence?.rebuild == nil ? nil : "regenerated on demand")
        case .dependency:
            return .init(effort: .slow, estimate: String(localized: "1–5 minutes"), action: String(localized: "reinstall dependencies"))
        case .buildOutput:
            return .init(effort: .slow, estimate: String(localized: "one build"), action: String(localized: "rebuild from source"))
        case .gitIgnored:
            return .init(effort: .quick, estimate: String(localized: "regenerated from tracked source"), action: nil)
        default:
            return .unknown
        }
    }
}
