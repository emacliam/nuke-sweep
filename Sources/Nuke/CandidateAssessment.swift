import Foundation
import CryptoKit

/// A local assessment explains evidence and uncertainty. It is not a cleanup
/// authorization, and AI output cannot promote its state or remove its blocks.
struct CandidateAssessment: Equatable, Sendable {
    /// Raw values are identity, not display text: they are compared in tests and
    /// could end up persisted. `title` carries the translatable name, the same
    /// split `Page` uses for its own stable raw values.
    enum State: String, Sendable {
        case checking = "Checking context"
        case measurementNeeded = "Measurement needed"
        case protected = "Protected"
        case inspectOnly = "Inspect only"
        case needsInspection = "Needs inspection"
        case reviewable = "Ready for review"

        var title: String {
            switch self {
            case .checking: return String(localized: "Checking context")
            case .measurementNeeded: return String(localized: "Measurement needed")
            case .protected: return String(localized: "Protected")
            case .inspectOnly: return String(localized: "Inspect only")
            case .needsInspection: return String(localized: "Needs inspection")
            case .reviewable: return String(localized: "Ready for review")
            }
        }
    }
    let id: String
    let state: State
    let reason: String
    let evidence: [String]
    let consequences: [String]
    let unknowns: [String]
    var canSelect: Bool { state == .needsInspection || state == .reviewable }
    static func make(_ item: DiskItem, evidence: CleanupEvidence?, scope: DeveloperScope? = nil, scopeBlocked: Bool = false) -> Self {
        let id = "item-" + SHA256.hash(data: Data(item.url.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        var facts = [String(localized: "Local filesystem metadata"), String(localized: "Identity and contents are rechecked during review")]
        if let evidence { facts.append(evidence.label + ": " + evidence.detail) }
        let unknowns = [String(localized: "Current use by every app or process is not established"), String(localized: "Logical size is not guaranteed reclaimed disk space")]
        let consequences = [String(localized: "Normal cleanup moves the reviewed item and its contents to Trash"), String(localized: "Space is not necessarily freed until Trash is emptied")] + (evidence?.rebuild.map { [$0] } ?? [])
        let state: State, reason: String
        if CleanupSafety.isSensitive(item.url.standardizedFileURL.path) {
            state = .protected; reason = String(localized: "This location contains protected personal, credential or source-control data.")
        } else if let evidence, evidence.kind.isBlocked {
            state = .protected; reason = evidence.detail
        } else if scopeBlocked || scope?.cleanupAllowed == false || scope?.blocksSelection(item) == true {
            state = .inspectOnly; reason = String(localized: "The current scope does not permit cleanup of this item or contains an exclusion.")
        } else if item.incomplete || item.measurementPending == true {
            state = .measurementNeeded; reason = String(localized: "Contents have not been completely measured. Measure a smaller folder or resolve access before review.")
        } else if evidence == nil {
            state = .checking; reason = String(localized: "Local context has not been inspected yet.")
        } else if evidence?.kind == .unknown {
            state = .needsInspection; reason = String(localized: "No reliable generated-file or cache evidence was found. Inspect the item and its purpose before proposing cleanup.")
        } else {
            state = .reviewable; reason = String(localized: "Local evidence suggests generated storage. Review still checks current contents, tracking, access and protected files.")
        }
        return .init(id: id, state: state, reason: reason, evidence: facts, consequences: consequences, unknowns: unknowns)
    }
}
