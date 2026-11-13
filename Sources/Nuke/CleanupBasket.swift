import Foundation

/// Session-owned proposals survive navigation. Nothing here grants cleanup
/// permission; the review and executor must independently revalidate each item.
struct CleanupBasket: Sendable {
    private(set) var items: [DiskItem] = []
    private(set) var proofs: [DuplicateProof] = []
    mutating func add(_ additions: [DiskItem], proofs newProofs: [DuplicateProof] = []) throws {
        var byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in additions { byPath[item.id] = item }
        let normalized = ReviewPlanner.topLevel(Array(byPath.values))
        guard normalized.count <= 1000 else { throw Failure.tooMany }
        var byDuplicate = Dictionary(uniqueKeysWithValues: proofs.map { ($0.duplicate.id, $0) })
        for proof in newProofs { byDuplicate[proof.duplicate.id] = proof }
        let retained = byDuplicate.values.filter { proof in normalized.contains { Self.covers($0, path: proof.duplicate.url.path) } }
        guard !retained.contains(where: { proof in normalized.contains { Self.covers($0, path: proof.keeper.url.path) } }) else { throw Failure.keeperConflict }
        items = normalized.sorted { $0.url.path < $1.url.path }; proofs = Array(retained)
    }
    mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
        proofs.removeAll { proof in !items.contains { Self.covers($0, path: proof.duplicate.url.path) } }
    }
    mutating func removeMoved(_ paths: [String]) {
        for item in items where paths.contains(where: { moved in item.url.path == moved || item.url.path.hasPrefix(moved + "/") }) { remove(item.id) }
    }
    mutating func clear() { items = []; proofs = [] }
    private static func covers(_ item: DiskItem, path: String) -> Bool {
        item.url.path == path || (item.directory && !item.symlink && path.hasPrefix(item.url.path + "/"))
    }
    enum Failure: LocalizedError {
        case tooMany, keeperConflict
        var errorDescription: String? {
            switch self {
            case .tooMany: return "The basket holds up to 1,000 top-level items. Review this batch before adding more."
            case .keeperConflict: return "This selection includes a duplicate keeper or its parent folder. Remove that selection before adding these copies; keepers must stay outside cleanup."
            }
        }
    }
}
